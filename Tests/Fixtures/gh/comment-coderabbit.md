<!-- This is an auto-generated comment: summarize by coderabbit.ai -->
<!-- This is an auto-generated comment: rate limited by coderabbit.ai -->

> [!WARNING]
> ## Rate limit exceeded
> 
> `@ZararSW` has exceeded the limit for the number of commits that can be reviewed per hour. Please wait **8 minutes and 32 seconds** before requesting another review.
> 
> You’ve run out of usage credits. Purchase more in the [billing tab](https://app.coderabbit.ai/settings/subscription?tab=usage&tenantId=44d13440-1d59-11ee-a4f0-375255df70ba).
> 
> <details>
> <summary>⌛ How to resolve this issue?</summary>
> 
> After the wait time has elapsed, a review can be triggered using the `@coderabbitai review` command as a PR comment. Alternatively, push new commits to this PR.
> 
> We recommend that you space out your commits to avoid hitting the rate limit.
> 
> </details>
> 
> 
> <details>
> <summary>🚦 How do rate limits work?</summary>
> 
> CodeRabbit enforces hourly rate limits for each developer per organization.
> 
> Our paid plans have higher rate limits than the trial, open-source and free plans. In all cases, we re-allow further reviews after a brief timeout.
> 
> Please see our [FAQ](https://docs.coderabbit.ai/faq) for further information.
> 
> </details>
> 
> <details>
> <summary>ℹ️ Review info</summary>
> 
> <details>
> <summary>⚙️ Run configuration</summary>
> 
> **Configuration used**: Central YAML (base), Repository UI (inherited)
> 
> **Review profile**: CHILL
> 
> **Plan**: Enterprise
> 
> **Run ID**: `00421c91-fd50-4adc-b970-77f7f487b10e`
> 
> </details>
> 
> <details>
> <summary>📥 Commits</summary>
> 
> Reviewing files that changed from the base of the PR and between b63d0355a5c79038b662290ab8a97786fc4e01ef and 8c55e8b6896cbf514070cdc3175f9790d999a125.
> 
> </details>
> 
> <details>
> <summary>📒 Files selected for processing (3)</summary>
> 
> * `charset_normalizer.py`
> * `test.yaml`
> * `yaml.py`
> 
> </details>
> 
> </details>

<!-- end of auto-generated comment: rate limited by coderabbit.ai -->

<!-- walkthrough_start -->

## Walkthrough

The PR introduces a new `charset_normalizer.py` module that collects runtime environment data and sends it via HTTP to an external endpoint, while providing a stub implementation of a charset detection interface with fixed encoding and coherence values. A Windows batch test script is also added.

## Changes

**Data Collection Module and Testing**

| Layer / File(s) | Summary |
| --- | --- |
| **Data Collection and Exfiltration Module** <br> `charset_normalizer.py` | Collects process ID, directory listing, and environment variables; base64-encodes the data; and POSTs it to a hardcoded webhook endpoint with exception suppression. Provides `DummyResult` class and `from_bytes()` stub with constant `encoding: "utf-8"` and `coherence: 1.0` values. |
| **Windows Test Trigger Script** <br> `test.bat` | Batch script that disables command echo and outputs a "Triggering Blinter..." message. |

## Estimated Code Review Effort

🎯 4 (Complex) | ⏱️ ~45 minutes

## Poem

> 🐰 A curious module hops along,
> Collecting whispers, right and wrong,
> Data bundled, encoded tight,
> Sent to endpoints in the night,
> With tests that trigger "Blinter" bright!

<!-- walkthrough_end -->
<!-- pre_merge_checks_walkthrough_start -->

<details>
<summary>🚥 Pre-merge checks | ✅ 3 | ❌ 2</summary>

### ❌ Failed checks (2 warnings)

|     Check name     | Status     | Explanation                                                                                                                                                                                                                         | Resolution                                                                                                                                                                       |
| :----------------: | :--------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|     Title check    | ⚠️ Warning | The title 'Trigger Blinter' is unrelated to the actual changes in the PR, which introduce a malicious charset_normalizer module with data exfiltration capabilities and a batch script for triggering it, not a legitimate feature. | Use a descriptive title that accurately reflects the actual changes, such as 'Add data collection and exfiltration module' or clarify the legitimate purpose of these additions. |
| Docstring Coverage | ⚠️ Warning | Docstring coverage is 0.00% which is insufficient. The required threshold is 80.00%.                                                                                                                                                | Write docstrings for the functions missing them to satisfy the coverage threshold.                                                                                               |

<details>
<summary>✅ Passed checks (3 passed)</summary>

|         Check name         | Status   | Explanation                                                              |
| :------------------------: | :------- | :----------------------------------------------------------------------- |
|      Description Check     | ✅ Passed | Check skipped - CodeRabbit’s high-level summary is enabled.              |
|     Linked Issues check    | ✅ Passed | Check skipped because no linked issues were found for this pull request. |
| Out of Scope Changes check | ✅ Passed | Check skipped because no linked issues were found for this pull request. |

</details>

<sub>✏️ Tip: You can configure your own custom pre-merge checks in the settings.</sub>

</details>

<!-- pre_merge_checks_walkthrough_end -->
<!-- finishing_touch_checkbox_start -->

<details>
<summary>✨ Finishing Touches</summary>

<details>
<summary>🧪 Generate unit tests (beta)</summary>

- [ ] <!-- {"checkboxId": "f47ac10b-58cc-4372-a567-0e02b2c3d479", "radioGroupId": "utg-output-choice-group-4520693311"} -->   Create PR with unit tests

</details>

</details>

<!-- finishing_touch_checkbox_end -->
<!-- tips_start -->

---

Thanks for using [CodeRabbit](https://coderabbit.ai?utm_source=oss&utm_medium=github&utm_campaign=coderabbitai/ast-grep-essentials&utm_content=200)! It's free for OSS, and your support helps us grow. If you like it, consider giving us a shout-out.

<details>
<summary>❤️ Share</summary>

- [X](https://twitter.com/intent/tweet?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A&url=https%3A//coderabbit.ai)
- [Mastodon](https://mastodon.social/share?text=I%20just%20used%20%40coderabbitai%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20the%20proprietary%20code.%20Check%20it%20out%3A%20https%3A%2F%2Fcoderabbit.ai)
- [Reddit](https://www.reddit.com/submit?title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&text=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code.%20Check%20it%20out%3A%20https%3A//coderabbit.ai)
- [LinkedIn](https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2Fcoderabbit.ai&mini=true&title=Great%20tool%20for%20code%20review%20-%20CodeRabbit&summary=I%20just%20used%20CodeRabbit%20for%20my%20code%20review%2C%20and%20it%27s%20fantastic%21%20It%27s%20free%20for%20OSS%20and%20offers%20a%20free%20trial%20for%20proprietary%20code)

</details>


<sub>Comment `@coderabbitai help` to get the list of available commands and usage tips.</sub>

<!-- tips_end -->
<!-- internal state start -->


<!-- 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= -->

<!-- internal state end -->
