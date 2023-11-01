## Description

<!-- Explain what was changed.  For example:
_Updated rounding in `removeQuoteToken` to round to token precision._ -->

## Purpose

<!-- Explain why the change was made, citing any issues where appropriate.  For example:
_Resolves audit issue M-333: Removal of quote token may leave dust amounts._
Or, if the change does not affect deployed contracts: _Resolve rounding issue with invariant E9 to handle tokens with less than 8 decimals._ -->

## Impact

<!-- State technical consequences of the change, whether beneficial or detrimental.  For example:
_Small increase in `removeQuoteToken` gas cost._
If the change does not affect deployed contracts, feel free to leave _none_. -->

## Tasks

- [ ] Changes to protocol contracts are covered by unit tests executed by CI.
- [ ] Protocol contract size limits have not been exceeded.
- [ ] Gas consumption for impacted transactions have been compared with the target branch, and nontrivial changes cited in the _Impact_ section above.
- [ ] Scope labels have been assigned as appropriate.
- [ ] Invariant tests have been manually executed as appropriate for the nature of the change.
