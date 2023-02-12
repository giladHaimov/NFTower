//truffle migrate --compile-none --reset
const NFTower = artifacts.require("./contracts/NFTower_base_contract.sol");


module.exports = async function(deployer) {
  await deployer.deploy(NFTower);
};
