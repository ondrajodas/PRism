Thanks for the PR, @maxbeizer! 🍻 It's great.

Note that some of these comments are best to be resolved in a follow up PR, as they'd break the base for the `discussion view` PR.


Summary of my comments (you can find the details in their corresponding comments):
- Add tests for discussion client methods.
- Add `--search` option.
- Add `--sort` and `--order` options.
- Add `--after` option for further pagination calls, and the `next` field in JSON output. We should basically do what we planned for pagination in `discussion view` (in https://github.com/cli/cli/issues/12810#issuecomment-4154772163).
- Some domain-vs-API and domain-vs-CLI adaptions.
- Question around having `hasDiscussionsEnabled` next to `discussions`; does that even work on repos where discussions are disabled.
- A bit around `--help` docs; `(preview)` note, examples, and command usage format.


### Further questions, but not ready to comment/share for now
- Shouldn't `ClosedAt` and `AnswerChosenAt` fields be `null`-able?
- What happens to ghost users in `author.login` query?
- See if we can replace the plain text GQL query with a strongly-typed one.

