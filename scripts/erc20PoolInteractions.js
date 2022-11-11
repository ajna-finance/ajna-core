const Web3 = require("web3");

const { FACTORY, ERC20POOL, ERC20TOKEN } = require('./abis.js');

async function main() {

  /**********************/
  /*** Contracts setup ***/
  /**********************/

  const web3 = new Web3(
    new Web3.providers.HttpProvider(
      process.env.ETH_RPC_URL
    )
  );

  const quoteToken = new web3.eth.Contract(
    ERC20TOKEN,
    process.env.QUOTE_ADDRESS
  );
  const collateralToken = new web3.eth.Contract(
    ERC20TOKEN,
    process.env.COLLATERAL_ADDRESS
  );
  const factory = new web3.eth.Contract(
    FACTORY.abi,
    process.env.ERC20_FACTORY
  );

  const poolAddress = await factory.methods.deployedPools(
    web3.utils.keccak256("ERC20_NON_SUBSET_HASH").toString('hex'),
    process.env.COLLATERAL_ADDRESS,
    process.env.QUOTE_ADDRESS
  ).call();
  console.log(`Interacting with pool ${poolAddress}`);
  const pool = new web3.eth.Contract(
    ERC20POOL.abi,
    poolAddress
  );

  /****************************/
  /*** Lender account setup ***/
  /****************************/
  const allowance = web3.utils.toWei(String(100000000), 'ether');
  const lender = web3.eth.accounts.privateKeyToAccount(
    process.env.LENDER_PRIVATE_KEY
  );
  web3.eth.accounts.wallet.add(lender);
  // approve pool to spend quote tokens
  await quoteToken.methods.approve(
    poolAddress,
    allowance
    ).send({
      from: process.env.LENDER_ADDRESS,
      gas: 200000,
    });

  
  /******************************/
  /*** Borrower account setup ***/
  /******************************/

  const borrower = web3.eth.accounts.privateKeyToAccount(
    process.env.BORROWER_PRIVATE_KEY
  );
  web3.eth.accounts.wallet.add(borrower);
  // approve pool to spend collateral tokens
  await collateralToken.methods.approve(
    poolAddress,
    allowance
    ).send({
      from: process.env.BORROWER_ADDRESS,
      gas: 200000,
    });
  // approve pool to spend quote tokens (for repay)
  await quoteToken.methods.approve(
    poolAddress,
    allowance
    ).send({
      from: process.env.BORROWER_ADDRESS,
      gas: 200000,
    });


  /************************/
  /*** Add quote tokens ***/
  /************************/

  const quoteAmount = web3.utils.toWei(String(10000), 'ether');
  const bucketIndex = 2000; // index 2000 = price

  await pool.methods.addQuoteToken(
    quoteAmount,
    bucketIndex
    ).send({
      from: process.env.LENDER_ADDRESS,
      gas: 2000000,
    })
    .once("transactionHash", (txhash) => {
      console.log(`Lender added ${quoteAmount} quote token to the pool`);
    });

  logLenderBalances(quoteToken)

  /************************/
  /*** Borrow from pool ***/
  /************************/

  // pledge collateral
  const collateralToPledge = web3.utils.toWei(String(100), 'ether');
  await pool.methods.pledgeCollateral(
    process.env.BORROWER_ADDRESS,
    collateralToPledge
    ).send({
      from: process.env.BORROWER_ADDRESS,
      gas: 2000000,
    })
    .once("transactionHash", (txhash) => {
      console.log(`Borrower pledged ${collateralToPledge} collateral in the pool`);
    });

  // borrow quote tokens
  const amountToBorrow = web3.utils.toWei(String(1000), 'ether');
  await pool.methods.borrow(
    amountToBorrow,
    5000 // limit bucket price index, if borrow happens to a higher price tx will fail
    ).send({
      from: process.env.BORROWER_ADDRESS,
      gas: 2000000,
    })
    .once("transactionHash", (txhash) => {
      console.log(`Borrower borrowed ${amountToBorrow} quote tokens from the pool`);
    });

  logBorrowerBalances(collateralToken, quoteToken)

  // repay loan with debt
  await pool.methods.repay(
    process.env.BORROWER_ADDRESS,
    web3.utils.toWei(String(1015), 'ether')
    ).send({
      from: process.env.BORROWER_ADDRESS,
      gas: 2000000,
    })
    .once("transactionHash", (txhash) => {
      console.log(`Borrower repaid loan`);
    });

  logBorrowerBalances(collateralToken, quoteToken)

  await pool.methods.pullCollateral(
    collateralToPledge
    ).send({
      from: process.env.BORROWER_ADDRESS,
      gas: 2000000,
    })
    .once("transactionHash", (txhash) => {
      console.log(`Borrower pulled their collateral from pool`);
    });

  logBorrowerBalances(collateralToken, quoteToken)

  /***************************/
  /*** Remove quote tokens ***/
  /***************************/

  await pool.methods.removeQuoteToken(
    allowance, // max amount
    bucketIndex
    ).send({
      from: process.env.LENDER_ADDRESS,
      gas: 2000000,
    })
    .once("transactionHash", (txhash) => {
      console.log(`Lender removed all quote tokens from the pool`);
    });

  logLenderBalances(quoteToken)

}

require("dotenv").config();
main();

async function logBorrowerBalances(collateralToken, quoteToken) {
  const borrowerCollateralBalance = await collateralToken.methods.balanceOf(
    process.env.BORROWER_ADDRESS
  ).call();
  const borrowerQuoteBalance = await quoteToken.methods.balanceOf(
    process.env.BORROWER_ADDRESS
  ).call();
  console.log(`Borrower quote balance: ${borrowerQuoteBalance} , collateral balance: ${borrowerCollateralBalance}`);
}

async function logLenderBalances(quoteToken) {
  const quoteBalance = await quoteToken.methods.balanceOf(
    process.env.LENDER_ADDRESS
  ).call();
  console.log(`Lender quote balance: ${quoteBalance}`);
}
