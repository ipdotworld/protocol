// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {WorkflowStructs} from "@storyprotocol/periphery/lib/WorkflowStructs.sol";
import {IRegistrationWorkflows} from "@storyprotocol/periphery/interfaces/workflows/IRegistrationWorkflows.sol";
import {ILicensingModuleWithNFT} from "./interfaces/ILicensingModuleWithNFT.sol";
import {ILicenseAttachmentWorkflows} from
    "@storyprotocol/periphery/interfaces/workflows/ILicenseAttachmentWorkflows.sol";
import {Licensing} from "@storyprotocol/core/lib/Licensing.sol";
import {ISPGNFT} from "@storyprotocol/periphery/interfaces/ISPGNFT.sol";

import {PILTerms, IPILicenseTemplate} from "@storyprotocol/core/interfaces/modules/licensing/IPILicenseTemplate.sol";
import {ILicensingModule} from "@storyprotocol/core/interfaces/modules/licensing/ILicensingModule.sol";
import {IIPAssetRegistry} from "@storyprotocol/core/interfaces/registries/IIPAssetRegistry.sol";
import {PermissionHelper} from "../lib/protocol-periphery-v1/contracts/lib/PermissionHelper.sol";
import {LicensingHelper} from "../lib/protocol-periphery-v1/contracts/lib/LicensingHelper.sol";
import {IAccessController} from "@storyprotocol/core/interfaces/access/IAccessController.sol";
import {IIPAccount} from "@storyprotocol/core/interfaces/IIPAccount.sol";
import {AccessPermission} from "@storyprotocol/core/lib/AccessPermission.sol";

import {IWETH9} from "./interfaces/IWETH9.sol";
import {Constants} from "../utils/Constants.sol";
import {IStoryHuntV3SwapCallback} from "./interfaces/storyhunt/IStoryHuntV3SwapCallback.sol";

import {IIPWorld} from "./interfaces/IIPWorld.sol";
import {PoolAddress} from "./lib/storyhunt/PoolAddress.sol";
import {Errors} from "./lib/Errors.sol";

/// @title Operator
/// @notice Frontend operator contract for authorized state transitions and IP management
/// @dev Handles signature-based operations, IP registration, and swap callbacks. Uses EIP712 for signatures.
contract Operator is IStoryHuntV3SwapCallback, EIP712, Nonces, Ownable2Step, IERC721Receiver {
    /// @notice Authorizes valid token creations
    bytes32 internal constant CREATE_IP_TOKEN_TYPEHASH =
        keccak256("CREATE(address creator,int24[] startTick,uint256[] allocationList,uint256 nonce,uint256 deadline)");

    /// @notice Authorizes verification of preregistered IP registrations
    bytes32 internal constant REGISTER_IP_CLAIM_TOKENS_TYPEHASH = keccak256(
        "REGISTER(address creator,bytes32 ipaHash,address claimer,address[] tokens,uint256 nonce,uint256 deadline)"
    );

    /// @notice Authorizes linking of tokens to a verified or claimed IP
    bytes32 internal constant LINK_TOKEN_TYPEHASH =
        keccak256("LINK(address sender,address ipaId,address[] tokens,uint256 nonce,uint256 deadline)");

    /// @notice Authorizes claiming IP assets with token linking
    bytes32 internal constant CLAIM_IP_TYPEHASH =
        keccak256("CLAIM(address sender,address ipaId,address claimer,address[] tokens,uint256 nonce,uint256 deadline)");

    /// @notice Fee value for LP pools (this is equivalent to a 0.3% fee)
    uint24 public constant V3_FEE = 3000;

    /// @notice Address of base token used for LP pairing
    address private immutable _weth;

    /// @notice Address of the IP World contract
    IIPWorld public immutable ipWorld;

    /// @notice Address of StoryHunt v3 pool deployer contract
    address private immutable _v3Deployer;

    /// @notice Used for storing IPA metadata during verified IP registration
    address public immutable spgNft;

    /// @notice The royalty policy address for IP World's custom royalty implementation
    address public immutable royaltyPolicy;

    /// @notice The licensing URL for IP World's licensing terms
    string public licensingUrl;

    /// @notice Gets the expected signer for the operator
    address public expectedSigner;

    /// @notice Emitted when the expected signer is updated
    /// @param oldSigner Previous expected signer address
    /// @param newSigner New expected signer address
    event ExpectedSignerUpdated(address indexed oldSigner, address indexed newSigner);

    /// @notice Emitted when license tokens are transferred
    /// @param to Recipient address
    /// @param tokenIds Array of transferred token IDs
    event LicenseTokensTransferred(address indexed to, uint256[] tokenIds);

    constructor(
        address weth_,
        address ipWorld_,
        address v3Deployer_,
        address spgNft_,
        address royaltyPolicy_,
        string memory licensingUrl_
    ) EIP712("IPWorldOperator", "1.0.0") Ownable(msg.sender) {
        if (weth_ == address(0) || ipWorld_ == address(0) || spgNft_ == address(0) || v3Deployer_ == address(0)) {
            revert Errors.Operator_InvalidAddress();
        }
        _weth = weth_;
        ipWorld = IIPWorld(ipWorld_);
        spgNft = spgNft_;
        _v3Deployer = v3Deployer_;
        royaltyPolicy = royaltyPolicy_;
        licensingUrl = licensingUrl_;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Sets the expected signer for the operator
    function setExpectedSigner(address expectedSigner_) external onlyOwner {
        if (expectedSigner_ == address(0)) {
            revert Errors.Operator_InvalidAddress();
        }
        address oldSigner = expectedSigner;
        expectedSigner = expectedSigner_;
        emit ExpectedSignerUpdated(oldSigner, expectedSigner_);
    }

    /// @notice Transfers multiple license tokens from this contract to a recipient
    /// @dev Only callable by contract owner, useful for migrating license tokens to new operator
    /// @param to The recipient address
    /// @param tokenIds Array of license token IDs to transfer
    function transferLicenseTokens(address to, uint256[] calldata tokenIds) external onlyOwner {
        if (to == address(0)) {
            revert Errors.Operator_InvalidAddress();
        }
        address licenseToken = ILicensingModuleWithNFT(Constants.LICENSING_MODULE).LICENSE_NFT();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(licenseToken).safeTransferFrom(address(this), to, tokenIds[i]);
        }
        emit LicenseTokensTransferred(to, tokenIds);
    }

    function createIpTokenWithSig(
        string calldata name,
        string calldata symbol,
        address ipaId,
        int24[] calldata startTickList,
        uint256[] calldata allocationList,
        uint256 deadline,
        Signature memory signature
    ) external payable returns (address pool, address token) {
        if (block.timestamp > deadline) {
            revert Errors.Operator_ERC2612ExpiredSignature(deadline);
        }
        _checkSigner(
            keccak256(
                abi.encode(
                    CREATE_IP_TOKEN_TYPEHASH,
                    msg.sender,
                    keccak256(abi.encodePacked(startTickList)),
                    keccak256(abi.encodePacked(allocationList)),
                    _useNonce(msg.sender),
                    deadline
                )
            ),
            signature
        );

        (pool, token) = ipWorld.createIpToken(msg.sender, name, symbol, ipaId, startTickList, allocationList);

        if (msg.value > 0) {
            // @dev msg.value can't be greater than type(int256).max
            IUniswapV3Pool(pool).swap(
                msg.sender,
                !(token < _weth),
                int256(msg.value),
                token < _weth ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1,
                abi.encode(token)
            );
        }
        _transferETH(msg.sender, address(this).balance);
    }

    /// @notice Authorizes registration of a preregistered IP into IP world
    /// @dev On verified registration, a story IPA is created in the process
    function registerAndClaimTokenWithSig(
        WorkflowStructs.IPMetadata calldata ipMetadata,
        address claimer,
        address[] memory tokens,
        uint256 deadline,
        Signature memory signature
    ) external returns (address) {
        if (block.timestamp > deadline) {
            revert Errors.Operator_ERC2612ExpiredSignature(deadline);
        }

        WorkflowStructs.LicenseTermsData[] memory licenseTermsData = new WorkflowStructs.LicenseTermsData[](1);

        licenseTermsData[0] = WorkflowStructs.LicenseTermsData({
            terms: PILTerms({
                transferable: true,
                royaltyPolicy: address(royaltyPolicy),
                defaultMintingFee: 0,
                expiration: 0,
                commercialUse: true,
                commercialAttribution: true,
                commercializerChecker: address(0),
                commercializerCheckerData: "",
                commercialRevShare: 0,
                commercialRevCeiling: 0,
                derivativesAllowed: false,
                derivativesAttribution: false,
                derivativesApproval: false,
                derivativesReciprocal: false,
                derivativeRevCeiling: 0,
                currency: _weth,
                uri: licensingUrl
            }),
            licensingConfig: Licensing.LicensingConfig({
                isSet: true,
                mintingFee: 0,
                licensingHook: address(0),
                hookData: "",
                commercialRevShare: 0,
                disabled: false,
                expectMinimumGroupRewardShare: 0,
                expectGroupRewardPool: address(0)
            })
        });

        bytes32 hash = ipMetadata.ipMetadataHash;

        _checkSigner(
            keccak256(
                abi.encode(
                    REGISTER_IP_CLAIM_TOKENS_TYPEHASH,
                    msg.sender,
                    hash,
                    claimer,
                    keccak256(abi.encodePacked(tokens)),
                    _useNonce(msg.sender),
                    deadline
                )
            ),
            signature
        );

        //Mint, register the IPA, attach custom PIL Terms and transfer IPA to Operator
        (address ipaId, uint256 tokenId, uint256[] memory licenseTermsIds) = ILicenseAttachmentWorkflows(
            Constants.LICENSE_ATTACHMENT_WORKFLOWS
        ).mintAndRegisterIpAndAttachPILTerms(spgNft, address(this), ipMetadata, licenseTermsData, false);

        //Mint 1 License Token and transfer it to Operator
        ILicensingModuleWithNFT(Constants.LICENSING_MODULE).mintLicenseTokens(
            ipaId,
            Constants.PILICENSE_TEMPLATE,
            licenseTermsIds[0],
            1,
            address(this),
            "",
            type(uint256).max,
            type(uint32).max
        );

        ipWorld.linkTokensToIp(ipaId, tokens);
        ipWorld.claimIp(ipaId, claimer);

        //Transfer the IPA to the IP Owner
        ISPGNFT(spgNft).safeTransferFrom(address(this), msg.sender, tokenId);

        return ipaId;
    }

    /// @notice Links tokens to a verified or claimed IP
    function linkTokenToIpWithSig(address ipaId, address[] memory tokens, uint256 deadline, Signature memory signature)
        external
    {
        if (block.timestamp > deadline) {
            revert Errors.Operator_ERC2612ExpiredSignature(deadline);
        }

        _checkSigner(
            keccak256(abi.encode(LINK_TOKEN_TYPEHASH, msg.sender, ipaId, tokens, _useNonce(msg.sender), deadline)),
            signature
        );

        ipWorld.linkTokensToIp(ipaId, tokens);
    }

    /// @notice Claims an existing IP asset and links tokens to it with signature verification
    /// @dev Requires IP asset owner to have approved this contract for license token minting
    /// @param ipaId Address of the existing IP asset
    /// @param claimer Address to claim the IP asset for
    /// @param tokens Array of token addresses to link to the IP asset
    /// @param deadline Signature expiration timestamp
    /// @param operatorSignature EIP712 signature for Operator verification (expectedSigner)
    /// @param ipOwnerSignature EIP712 signature for IP licensing permissions (IP owner)
    function claimIpWithSig(
        address ipaId,
        address claimer,
        address[] calldata tokens,
        uint256 deadline,
        Signature memory operatorSignature,
        Signature memory ipOwnerSignature
    ) external {
        if (ipaId == address(0) || claimer == address(0)) {
            revert Errors.Operator_InvalidAddress();
        }

        if (block.timestamp > deadline) {
            revert Errors.Operator_ERC2612ExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(
            abi.encode(
                CLAIM_IP_TYPEHASH,
                msg.sender,
                ipaId,
                claimer,
                keccak256(abi.encodePacked(tokens)),
                _useNonce(msg.sender),
                deadline
            )
        );
        _checkSigner(structHash, operatorSignature);

        // First attach our license terms to the IP asset
        WorkflowStructs.LicenseTermsData[] memory licenseTermsData = new WorkflowStructs.LicenseTermsData[](1);
        licenseTermsData[0] = WorkflowStructs.LicenseTermsData({
            terms: PILTerms({
                transferable: true,
                royaltyPolicy: address(royaltyPolicy),
                defaultMintingFee: 0,
                expiration: 0,
                commercialUse: true,
                commercialAttribution: true,
                commercializerChecker: address(0),
                commercializerCheckerData: "",
                commercialRevShare: 0,
                commercialRevCeiling: 0,
                derivativesAllowed: false,
                derivativesAttribution: false,
                derivativesApproval: false,
                derivativesReciprocal: false,
                derivativeRevCeiling: 0,
                currency: _weth,
                uri: licensingUrl
            }),
            licensingConfig: Licensing.LicensingConfig({
                isSet: true,
                mintingFee: 0,
                licensingHook: address(0),
                hookData: "",
                commercialRevShare: 0,
                disabled: false,
                expectMinimumGroupRewardShare: 0,
                expectGroupRewardPool: address(0)
            })
        });

        // Use registerPILTermsAndAttach internal logic directly to bypass msg.sender check

        // Get the actual IP owner from the IP Account's underlying NFT
        IIPAccount ipAccount = IIPAccount(payable(ipaId));
        (, address tokenContract, uint256 tokenId) = ipAccount.token();
        address actualIpOwner = IERC721(tokenContract).ownerOf(tokenId);

        // Create signature data using the IP owner's signature for licensing permissions
        WorkflowStructs.SignatureData memory sigAttachAndConfig = WorkflowStructs.SignatureData({
            signer: actualIpOwner, // The actual IP owner from NFT ownership
            deadline: deadline,
            signature: abi.encodePacked(ipOwnerSignature.r, ipOwnerSignature.s, ipOwnerSignature.v)
        });

        // Step 1: Set permissions for LicensingModule operations
        // Create permission list
        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](2);
        permissionList[0] = AccessPermission.Permission({
            ipAccount: ipaId,
            signer: address(this), // Operator as signer
            to: Constants.LICENSING_MODULE,
            func: ILicensingModule.attachLicenseTerms.selector,
            permission: AccessPermission.ALLOW
        });
        permissionList[1] = AccessPermission.Permission({
            ipAccount: ipaId,
            signer: address(this), // Operator as signer
            to: Constants.LICENSING_MODULE,
            func: ILicensingModule.setLicensingConfig.selector,
            permission: AccessPermission.ALLOW
        });

        // Set permissions using executeWithSig
        IIPAccount(payable(ipaId)).executeWithSig(
            Constants.ACCESS_CONTROLLER,
            0,
            abi.encodeWithSelector(IAccessController.setBatchTransientPermissions.selector, permissionList),
            sigAttachAndConfig.signer,
            sigAttachAndConfig.deadline,
            sigAttachAndConfig.signature
        );

        // Step 2: Register, attach, and set configs directly (LicensingHelper internal logic)

        // Register PIL terms
        IPILicenseTemplate pilTemplate = IPILicenseTemplate(Constants.PILICENSE_TEMPLATE);
        uint256 licenseTermsId = pilTemplate.registerLicenseTerms(licenseTermsData[0].terms);

        // Attach license terms
        ILicensingModule licensingModule = ILicensingModule(Constants.LICENSING_MODULE);
        try licensingModule.attachLicenseTerms(ipaId, Constants.PILICENSE_TEMPLATE, licenseTermsId) {
            // license terms are attached successfully
        } catch (bytes memory reason) {
            // if the error is not that the license terms are already attached, revert with the original error
            if (bytes4(reason) != 0x650aa092) {
                // LicenseRegistry__LicenseTermsAlreadyAttached selector
                assembly {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }

        // Set licensing configuration if provided
        if (licenseTermsData[0].licensingConfig.isSet) {
            licensingModule.setLicensingConfig(
                ipaId, Constants.PILICENSE_TEMPLATE, licenseTermsId, licenseTermsData[0].licensingConfig
            );
        }

        uint256[] memory licenseTermsIds = new uint256[](1);
        licenseTermsIds[0] = licenseTermsId;

        // Mint 1 License Token using the newly attached license terms

        ILicensingModuleWithNFT(Constants.LICENSING_MODULE).mintLicenseTokens(
            ipaId,
            Constants.PILICENSE_TEMPLATE,
            licenseTermsIds[0], // Use the newly created license terms ID
            1,
            address(this),
            "",
            type(uint256).max,
            type(uint32).max
        );

        // Link tokens to IP and claim
        ipWorld.linkTokensToIp(ipaId, tokens);
        ipWorld.claimIp(ipaId, claimer);
    }

    function _checkSigner(bytes32 structHash, Signature memory sig) internal view {
        bytes32 _hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(_hash, sig.v, sig.r, sig.s);
        if (signer != expectedSigner) {
            revert Errors.Operator_ERC2612InvalidSigner(signer, expectedSigner);
        }
    }

    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _transferETH(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}("");
        if (!success) revert();
    }

    /// @notice Implementation of IERC721Receiver
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice Harvests fees for multiple tokens, continuing even if some fail
    /// @dev Uses try-catch to ensure all tokens are attempted even if some revert
    /// @param tokens Array of token addresses to harvest
    /// @return successes Array indicating which harvests succeeded
    /// @return results Array of error messages for failed harvests (empty string if successful)
    function harvestTokens(address[] calldata tokens)
        external
        returns (bool[] memory successes, string[] memory results)
    {
        uint256 length = tokens.length;
        successes = new bool[](length);
        results = new string[](length);

        for (uint256 i = 0; i < length; i++) {
            try ipWorld.harvest(tokens[i]) {
                successes[i] = true;
                results[i] = "";
            } catch Error(string memory reason) {
                successes[i] = false;
                results[i] = reason;
            } catch (bytes memory) {
                successes[i] = false;
                results[i] = "Unknown error";
            }
        }

        return (successes, results);
    }

    /// @notice Transfers tokens owed for a swap via the v3 swap callback
    /// @param amount0Delta Amount of token0 that was sent or to be received
    /// @param amount1Delta Amount of token1 that was sent or to be received
    function storyHuntV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        address token = abi.decode(data, (address));
        address poolAddr = PoolAddress.computeAddress(_v3Deployer, PoolAddress.getPoolKey(token, _weth, V3_FEE));
        if (msg.sender != poolAddr) {
            revert Errors.Operator_OnlyLiquidityPool();
        }

        uint256 transferAmount = uint256(amount0Delta > 0 ? amount0Delta : amount1Delta);
        IWETH9(_weth).deposit{value: transferAmount}();
        IERC20(_weth).transfer(msg.sender, transferAmount);
    }
}
