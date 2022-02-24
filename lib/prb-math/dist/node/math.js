"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const mathjs_1 = require("mathjs");
const math = (0, mathjs_1.create)({
    addDependencies: mathjs_1.addDependencies,
    bignumberDependencies: mathjs_1.bignumberDependencies,
    ceilDependencies: mathjs_1.ceilDependencies,
    expDependencies: mathjs_1.expDependencies,
    floorDependencies: mathjs_1.floorDependencies,
    logDependencies: mathjs_1.logDependencies,
    log10Dependencies: mathjs_1.log10Dependencies,
    log2Dependencies: mathjs_1.log2Dependencies,
    meanDependencies: mathjs_1.meanDependencies,
    modDependencies: mathjs_1.modDependencies,
    powDependencies: mathjs_1.powDependencies,
    sqrtDependencies: mathjs_1.sqrtDependencies,
}, {
    number: "BigNumber",
    precision: 60 + 18 + 2,
});
exports.default = math;
//# sourceMappingURL=math.js.map