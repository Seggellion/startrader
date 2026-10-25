# First-pagination history regression

v169 source: 6636ff5af84ccc289c0bfc55f78a12bda312418e.

A live read-only Google Chrome check found a case absent from the earlier multi-frame paging sequence:

| State | URL sell_page | Rendered Sell rows | Canonical snapshot sell_page |
| --- | ---: | ---: | ---: |
| Direct terminal 27 page | 1 | 50 | 1 |
| First Next Sell | 2 | 39 | 2 |
| Browser Back | 1 | 39 | 2 |

The confirmed result violated the playbook. v169 was rolled back to the compatible v168 slug as release v170, retaining the two additive indexes and all business data. Heroku rollback restores slug/config; no config var had been changed by this project between v168/v169.

The contract explicitly permits normal GET pagination when frame history is unreliable. The fix changes only paging targets to _top and adds this exact regression. Query scope, grouping, counts, player semantics, independent page parameters and automatic/explicit refresh are retained. Map/details reinitialize on page visits, the documented simplification tradeoff.

The first v169 observation had zero page/console errors or natural market-row messages over 600 seconds; bounded infrastructure samples had no 5xx/crashes. Those facts do not erase the functional history failure. The replacement source must pass the regression and a new postrelease observation before completion.
