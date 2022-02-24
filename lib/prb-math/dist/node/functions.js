"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.sqrt = exports.powu = exports.pow = exports.mul = exports.log2 = exports.log10 = exports.ln = exports.inv = exports.gm = exports.frac = exports.floor = exports.exp2 = exports.exp = exports.div = exports.ceil = exports.avg = void 0;
const decimal_js_1 = require("decimal.js");
const math_1 = __importDefault(require("./math"));
const constants_1 = require("./constants");
const helpers_1 = require("./helpers");
function avg(x, y) {
    const result = math_1.default.mean((0, helpers_1.toMbn)(x), (0, helpers_1.toMbn)(y));
    return (0, helpers_1.toEbn)(result);
}
exports.avg = avg;
function ceil(x) {
    const result = (0, helpers_1.toMbn)(x).ceil();
    return (0, helpers_1.toEbn)(result);
}
exports.ceil = ceil;
function div(x, y) {
    if (y.isZero()) {
        throw new Error("Cannot divide by zero");
    }
    const result = (0, helpers_1.toMbn)(x).div((0, helpers_1.toMbn)(y));
    return (0, helpers_1.toEbn)(result);
}
exports.div = div;
function exp(x) {
    const result = (0, helpers_1.toMbn)(x).exp();
    return (0, helpers_1.toEbn)(result);
}
exports.exp = exp;
function exp2(x) {
    const two = math_1.default.bignumber("2");
    const result = math_1.default.pow(two, (0, helpers_1.toMbn)(x));
    return (0, helpers_1.toEbn)(result);
}
exports.exp2 = exp2;
function floor(x) {
    const result = (0, helpers_1.toMbn)(x).floor();
    return (0, helpers_1.toEbn)(result);
}
exports.floor = floor;
function frac(x) {
    return (0, helpers_1.solidityMod)(x, constants_1.SCALE);
}
exports.frac = frac;
function gm(x, y) {
    const xy = (0, helpers_1.toMbn)(x).mul((0, helpers_1.toMbn)(y));
    if (xy.isNegative()) {
        throw new Error("PRBMath cannot calculate the geometric mean of a negative number");
    }
    const result = math_1.default.sqrt(xy);
    return (0, helpers_1.toEbn)(result);
}
exports.gm = gm;
function inv(x) {
    if (x.isZero()) {
        throw new Error("Cannot calculate the inverse of zero");
    }
    const one = math_1.default.bignumber("1");
    const result = one.div((0, helpers_1.toMbn)(x));
    return (0, helpers_1.toEbn)(result);
}
exports.inv = inv;
function ln(x) {
    if (x.isZero()) {
        throw new Error("Cannot calculate the natural logarithm of zero");
    }
    else if (x.isNegative()) {
        throw new Error("Cannot calculate the natural logarithm of a negative number");
    }
    const result = math_1.default.log((0, helpers_1.toMbn)(x));
    return (0, helpers_1.toEbn)(result);
}
exports.ln = ln;
function log10(x) {
    if (x.isZero()) {
        throw new Error("Cannot calculate the common logarithm of zero");
    }
    else if (x.isNegative()) {
        throw new Error("Cannot calculate the common logarithm of a negative number");
    }
    const result = math_1.default.log10((0, helpers_1.toMbn)(x));
    return (0, helpers_1.toEbn)(result);
}
exports.log10 = log10;
function log2(x) {
    if (x.isZero()) {
        throw new Error("Cannot calculate the binary logarithm of zero");
    }
    else if (x.isNegative()) {
        throw new Error("Cannot calculate the binary logarithm of a negative number");
    }
    const result = math_1.default.log2((0, helpers_1.toMbn)(x));
    return (0, helpers_1.toEbn)(result);
}
exports.log2 = log2;
function mul(x, y) {
    const result = (0, helpers_1.toMbn)(x).mul((0, helpers_1.toMbn)(y));
    return (0, helpers_1.toEbn)(result, decimal_js_1.Decimal.ROUND_HALF_UP);
}
exports.mul = mul;
function pow(x, y) {
    if (x.isNegative()) {
        throw new Error("PRBMath cannot raise a negative base to a power");
    }
    const result = math_1.default.pow((0, helpers_1.toMbn)(x), (0, helpers_1.toMbn)(y));
    return (0, helpers_1.toEbn)(result);
}
exports.pow = pow;
function powu(x, y) {
    const exponent = math_1.default.bignumber(String(y));
    const result = math_1.default.pow((0, helpers_1.toMbn)(x), exponent);
    return (0, helpers_1.toEbn)(result);
}
exports.powu = powu;
function sqrt(x) {
    if (x.isNegative()) {
        throw new Error("Cannot calculate the square root of a negative number");
    }
    const result = math_1.default.sqrt((0, helpers_1.toMbn)(x));
    return (0, helpers_1.toEbn)(result);
}
exports.sqrt = sqrt;
//# sourceMappingURL=functions.js.map