const Web3 = require("web3");

const { FACTORY } = require('./abis.js');

async function main() {
  // Configuring the connection to forked chain
  const web3 = new Web3(
    new Web3.providers.HttpProvider(
      process.env.ETH_RPC_URL
    )
  );

  /**********************/
  /*** Accounts setup ***/
  /**********************/

  const lender = web3.eth.accounts.privateKeyToAccount(
    process.env.LENDER_PRIVATE_KEY
  );
  web3.eth.accounts.wallet.add(lender);


  /*********************/
  /*** Pool creation ***/
  /*********************/

  const factory = new web3.eth.Contract(
    FACTORY.abi,
    process.env.ERC20_FACTORY
  );

  const interestRate = web3.utils.toWei(String(0.05), 'ether');
  const poolCreationTx = factory.methods.deployPool(
    process.env.COLLATERAL_ADDRESS,
    process.env.QUOTE_ADDRESS,
    interestRate
  );
  const poolCreationReceipt = await poolCreationTx
    .send({
      from: process.env.LENDER_ADDRESS,
      gas: await poolCreationTx.estimateGas(),
    })
    .once("transactionHash", (txhash) => {
      console.log(`Deploying pool ...`);
    });
  console.log(poolCreationReceipt);
  
  const poolAddress = await factory.methods.deployedPools(
    web3.utils.keccak256("ERC20_NON_SUBSET_HASH").toString('hex'),
    process.env.COLLATERAL_ADDRESS,
    process.env.QUOTE_ADDRESS
  ).call();
  console.log(`Created pool with address ${poolAddress}`);

}

require("dotenv").config();
main();
