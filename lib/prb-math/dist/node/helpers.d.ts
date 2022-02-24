import type { BigNumber as EthersBigNumber } from "@ethersproject/bignumber";
import { Decimal } from "decimal.js";
import type { BigNumber as MathjsBigNumber } from "mathjs";
export declare function solidityMod(x: EthersBigNumber, m: EthersBigNumber): EthersBigNumber;
export declare function toEbn(x: MathjsBigNumber, rm?: Decimal.Rounding): EthersBigNumber;
export declare function toMbn(x: EthersBigNumber): MathjsBigNumber;
//# sourceMappingURL=helpers.d.ts.map