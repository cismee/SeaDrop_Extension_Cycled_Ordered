// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC721SeaDrop } from "seadrop/ERC721SeaDrop.sol";

/**
 * @title  ERC721SeaDropCycled
 * @notice ERC721SeaDrop variant that cycles tokenURI over a fixed
 *         number of metadata files. Token ID N maps to metadata file
 *         ((N - 1) % totalFiles) + 1, so IPFS only needs `totalFiles` entries
 *         instead of millions.
 */
contract ERC721SeaDropCycled is ERC721SeaDrop {
    /// @notice The number of unique metadata files to cycle through.
    uint256 public immutable TOTAL_FILES;

    /// @notice Revert when totalFiles is zero.
    error TotalFilesIsZero();

    constructor(
        string memory name,
        string memory symbol,
        address[] memory allowedSeaDrop,
        uint256 _totalFiles
    ) ERC721SeaDrop(name, symbol, allowedSeaDrop) {
        if (_totalFiles == 0) revert TotalFilesIsZero();
        TOTAL_FILES = _totalFiles;
    }

    /**
     * @notice Returns the token URI for `tokenId`, cycling sequentially
     *         over 1..totalFiles.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI = _baseURI();
        if (bytes(baseURI).length == 0) {
            return "";
        }

        // If baseURI does not end in "/", return it as-is (pre-reveal).
        if (bytes(baseURI)[bytes(baseURI).length - 1] != bytes("/")[0]) {
            return baseURI;
        }

        uint256 fileId = ((tokenId - 1) % TOTAL_FILES) + 1;
        return string(abi.encodePacked(baseURI, _toString(fileId)));
    }
}