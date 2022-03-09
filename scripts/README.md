# Fund test address (created in MetaMask)

- replace '0x0F2D187b7606EdBd6e62f9E0e5A70f24e76212a9' with the address of account generated in MetaMask

```bash
brownie console
from scripts.fundsUtils import *
provide_borrower_funds('0x0F2D187b7606EdBd6e62f9E0e5A70f24e76212a9')
provide_lender_funds('0x0F2D187b7606EdBd6e62f9E0e5A70f24e76212a9')
```
