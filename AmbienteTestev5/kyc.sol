import "@parallelmarkets/token/contracts/IParallelID.sol";

contract MyContract {
    // 0x9ec6... is the address on Mainnet. For testing in the sandbox environment,
    // use the Goerli contract at 0x0F2255E8aD232c5740879e3B495EA858D93C3016
    address public PID_CONTRACT = 0x9ec6232742b6068ce733645AF16BA277Fa412B0A;

    function isSanctionsSafe(address subject) public view returns (bool) {
        // Get a handle for the Parallel Identity Token contract
        IParallelID pid = IParallelID(PID_CONTRACT);

        // It's possible a subject could have multiple tokens issued over time - check
        // to see if any are currently monitored and safe from sanctions
        for (uint256 i = 0; i < pid.balanceOf(subject); i++) {
            uint256 tokenId = pid.tokenOfOwnerByIndex(subject, i);
            if (pid.isSanctionsSafe(tokenId)) return true;
        }
        return false;
    }

    function currentlyAccredited(address subject) public view returns (bool) {
        // Get a handle for the Parallel Identity Token contract
        IParallelID pid = IParallelID(PID_CONTRACT);

        // It's possible a subject could have multiple tokens issued over time - check
        // to see if any have an "accredited" trait and were minted in the last 90 days
        // (US regulation says accreditation certification only lasts 90 days)
        for (uint256 i = 0; i < pid.balanceOf(subject); i++) {
            uint256 tokenId = pid.tokenOfOwnerByIndex(subject, i);
            bool recent = pid.mintedAt(tokenId) >= block.timestamp - 90 days;
            bool accredited = pid.hasTrait(tokenId, "accredited");
            if (recent && accredited) return true;
        }
        return false;
    }
}
