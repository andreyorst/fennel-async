Please read the following document to make collaborating on the project easier for both sides.

## Reporting bugs

If you've encountered a bug, do the following:

- Check if the documentation has information about the problem you have.
  Maybe this isn't a bug, but the desired behavior.
- Check past and current issues, maybe someone had reported your problem already.
  If there's no issue, describing your problem, or there is, but it is closed, please create a new issue, and link all closed issues that relate to this problem, if any.
- Tag issue with a `BUG:` at the beginning of the issue name.

## Suggesting features and/or changes

Before suggesting a feature, please check if this feature wasn't requested before.
You can do that in the issues, by filtering issues by `FEATURE:`.
If no feature is found, please file a new issue, and tag it with a `FEATURE:` at the beginning of the issue name.

## Contributing changes

Please do.

When deciding to contribute a large number of changes, first consider opening a `DISCUSSION:` type issue, so we could first decide if such dramatic changes are in the scope of the project.
This will save your time, in case such changes are out of the project's scope.

If you're contributing a bugfix, please open a `BUG:` issue first, unless someone already did that.
All bug-related merge requests must have a linked issue with a meaningful explanation and steps of reproducing a bug.
Small fixes are also welcome and don't require filing an issue, although we may ask you to do so.

### Writing code

When writing code, consider following the existing style without applying dramatic changes to formatting unless really necessary.
For this particular project, please follow rules as described in [Fennel Style Guide](https://git.sr.ht/~technomancy/fennel/tree/HEAD/style.md).
If you see any inconsistencies with the style guide in the code, feel free to change these in a non-breaking way.

If you've added new functions, each one must be covered with a set of tests.

When changing existing functions make sure that all tests pass.
If some tests do not pass, make sure that these tests are written to test this function.
If not, then, perhaps, you've broken something horribly.

Before committing changes, you must run tests with `make test`, and all tests must pass without errors.
Consider checking test coverage with `make luacov` and rendering it with your preferred reporter.
The Makefile also has a `luacov-console` target, which can be used to see coverage of Lua code directly in the terminal.

### Writing documentation

If you've added new code, make sure it is covered not only by tests but also by documentation.
Exported functions should be documented directly in the code, by using the docstring feature of the language.
This way this documentation can be exported to Markdown later on.
Private functions can be documented via comments in place of docstrings to save some space by not including docs for private functions in the compiler metadata table.

Documentation files use Markdown format, as it is widely supported and can be read without any special software.
Please make sure to follow the existing style of documentation, which can be shortly described as:

- One sentence per line.
  This makes it easier to see changes while browsing Git history.
- No indentation of text after headings.
  This makes little sense with a one-sentence per line approach anyway.
- No empty lines after headings.
- Amount of empty lines in the text should be:
  - Single empty lines between paragraphs.
  - Double empty lines before top-level headings.
  - Single empty lines before other headings.
- Consider using spell checking.
  If you find a word not known by the dictionary, please add it to the `LocalWords` section at the bottom of the document.

### Working with Git

Check out the new branch from the project's main development branch.
If you've cloned this project some time ago, consider checking if your branch has all recent changes from upstream.

When creating a merge request consider squashing your commits.
You may do this manually, or use Gitlab's "Squash commits" button.

<!-- LocalWords:  bugfix docstring comitting VSCode SublimeText Gitlab's LocalWords
 -->
