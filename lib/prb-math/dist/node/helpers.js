"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.toMbn = exports.toEbn = exports.solidityMod = void 0;
const decimal_js_1 = require("decimal.js");
const evm_bn_1 = require("evm-bn");
const constants_1 = require("./constants");
const math_1 = __importDefault(require("./math"));
function solidityMod(x, m) {
    const m_mbn = toMbn(m);
    let remainder = toMbn(x).mod(m_mbn);
    if (x.isNegative() && !remainder.isZero()) {
        remainder = remainder.sub(m_mbn);
    }
    return toEbn(remainder);
}
exports.solidityMod = solidityMod;
function toEbn(x, rm = decimal_js_1.Decimal.ROUND_DOWN) {
    const fixed = x.toFixed(Number(constants_1.DECIMALS), rm);
    return (0, evm_bn_1.toBn)(fixed, Number(constants_1.DECIMALS));
}
exports.toEbn = toEbn;
function toMbn(x) {
    return math_1.default.bignumber((0, evm_bn_1.fromBn)(x, Number(constants_1.DECIMALS)));
}
exports.toMbn = toMbn;
//# sourceMappingURL=helpers.js.map