const Web3 = require("web3");

// Loading the contract ABI
// (the results of a previous compilation step)
const fs = require("fs");
const { abi } = JSON.parse(fs.readFileSync("../brownie_out/contracts/ERC20PoolFactory.json"));

async function main() {
  // Configuring the connection to an Ethereum node
  const web3 = new Web3(
    new Web3.providers.HttpProvider(
      process.env.ETH_RPC_URL
    )
  );
  // Creating a signing account from a private key
  const signer = web3.eth.accounts.privateKeyToAccount(
    process.env.PRIVATE_KEY
  );
  web3.eth.accounts.wallet.add(signer);
  // Creating a Contract instance
  const contract = new web3.eth.Contract(
    abi,
    // Replace this with the address of your deployed contract
    process.env.ERC20_FACTORY
  );
  const interestRate = web3.utils.toWei(String(0.05), 'ether');
  const tx = contract.methods.deployPool(process.env.COMP, process.env.DAI, interestRate);
  const receipt = await tx
    .send({
      from: signer.address,
      gas: await tx.estimateGas(),
    })
    .once("transactionHash", (txhash) => {
      console.log(`Mining transaction ...`);
    });
  // The transaction is now on chain!
  console.log(receipt);
  
  const poolAddress = await contract.methods.deployedPools(web3.utils.keccak256("ERC20_NON_SUBSET_HASH").toString('hex'), process.env.COMP, process.env.DAI).call();
  
  console.log('poolAddress', poolAddress);
}

require("dotenv").config();
main();
