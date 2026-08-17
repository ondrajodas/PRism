### Context

- Linear issue: [COR-1775](https://linear.app/metalbear/issue/COR-1775/allow-the-intproxy-session-monitor-to-end-gracefully-on-session-end)
- Initial PR: https://github.com/metalbear-co/mirrord/pull/4677
- Internal discussion: [Slack](https://metalbear.slack.com/archives/C09HK8DDX7U/p1785946062959089)
- Fix working: [PH `client_session_v1` event](https://us.posthog.com/project/29024/events/019fec95-54ce-7073-9f6f-50e88f90bcde/2026-08-10T19%3A50%3A37.413000%2B03%3A00)
  - Additionally ran smoke tests for 20, 50, 100 concurrent runs and all analytics events were received in PH as expected

### Summary

- Analytics were not being reported due to `Drop` not executing when the session monitor was torn down
- The session monitor was not exiting gracefully because each `AppState` held a reference to `AnalyticsReporter`, so `drain` never fully closed it down
- With this change, the session monitor is given only `Weak` references to the `ChaosAnalyticsReporter` (which wraps `AnalyticsReporter`)
- Also as pointed out in the previous PR, the error was not being set on analytics when the intproxy failed on the first connection
