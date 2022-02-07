# ajna test suites

## Setup 1

4 lenders provide quote tokens in one price bucket

### Test1

- 5 borrowers all in one price bucket
- a lender come in at a higher price and covers entire debt

#### Expected

- All 5 borrowers are moved to the higher price / bucket

### Test2

- 50 borrowers all in one price bucket
- a lender comes in at a higher price and covers entire debt

#### Expected

- All 50 borrowers are moved to the higher price / bucket

## Setup 2

4 lenders provide quote tokens across two price buckets

### Test1

- 5 borrowers across two price buckets
- a lender comes in at a higher price and covers entire debt

#### Expected

- All 5 borrowers are moved to the higher price / bucket


### Test2

- 50 borrowers across two price buckets
- a lender comes in at a higher price and covers entire debt

#### Expected

- All 50 borrowers are moved to the higher price / bucket

## Setup 3

- 4 lenders provide quote tokens across 10 price buckets

### Test1

- 5 borrowers across 10 price buckets
- a lender comes in at a higher price and covers entire debt

#### Expected

- All 5 borrowers are moved to the higher price / bucket


### Test2

- 5 borrowers across 10 price buckets
- a lender comes in at a higher price and covers 1/2 debt

#### Expected

- borrowers debt is spread across buckets
