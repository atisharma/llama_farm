# llama-farm
Chat with multiple bots with different personalities, hosted locally
or with OpenAI, in the comfort of a beautiful 1970's terminal-themed
REPL.

![A llama with a cuttlefish logo standing in front of the letters LF](logo.png)

### Topical chat memory
Llama-farm has a **long-term chat memory** that recalls previous
conversations. A summary of previous conversation relevant to the
topic (automatically determined) is available to the active bot.

### Knowledge database
Ask it questions about your own documents and information, stored in a
local vector knowledge store. I recommend you are selective about
what you ingest in order to improve the relevance of results. The
quality of information available is more important than the quantity.

### Powerful long-text summarization
It can summarize long texts like Youtube video transcripts, URLs and
text files.  You can discuss the content of those sources and it can
extract the relevant parts.

### Internet sources
You can ask it questions with access to YouTube, arXiv, wikipedia,
URLs and text files.

### Compatibility and technology
Llama-farm speaks to any OpenAI-compatible API:

- oobabooga/text-generation-webui (via its OpenAI-compatible API extension)
- OpenAI
- lm-sys/FastChat (untested)
- keldenl/gpt-llama.cpp (untested)

The oobabooga solution with exllama is recommended because it's fast
and is what gets tested.

Llama-farm uses hwchase17/langchain for the vectordb abstraction and
splitting of long documents (see limitations).

The storage is backed by [faiss](https://github.com/facebookresearch/faiss). The wrapper to [chromadb](https://github.com/chroma-core/chroma) is
written but is not currently used or tested.

### Help text
The help text is [here](llama_farm/help.md).

### Changelog

[See the changelog here](Changelog.md)

**BREAKING CHANGES**:
- the default embedding for the vector db changed in 0.6.0
to allow longer text fragments. You'll either need to replace your old vector
dbs (under `storage/`) or change back the embedding and chunk sizes under the
storage section in the config file. Other format changes in the config file
need to be reflected in your config also (see [the example
config](config.toml.example)).
- Also, the config file format has changed since 0.7.0, since using the OpenAI API directly.

### Setup
Copy the `config.toml.example` to `config.toml`.
To use openAI, you need to set your key in `config.toml`.

There are a lot of dependencies so it's recommended you install
everything in a virtual environment.  Either clone the repo, install
the `requirements.txt` and run the module
```
$ <activate your venv>
$ git clone https://github.com/atisharma/llama_farm
$ cd llama_farm
$ pip install -r requirements.txt
$ python -m llama_farm
```

Or, install using pip
```
$ <activate your venv>
$ pip install git+https://github.com/atisharma/llama_farm
$ llama-farm
```

If you want to use bark TTS on a different cuda device from your
language inference one, you can set the environment variable
`CUDA_VISIBLE_DEVICES` to point to the appropriate graphics card
before you run llama-farm. For example, run the LLM server on one
graphics card and llama-farm's TTS on a weaker one.

### Suitable models
Llama-farm works very well with OpenAI's gpt-3.5-turbo.
Wizard-Vicuna-Uncensored, WizardLM, etc also work very well. It even
works surprisingly well with WizardLM-7B!  But see limitations below.

### Limitations and bugs
- Larger LLaMA models (30B) work much better for complex tasks.
- The context length limitation of Llama models (2048 tokens) is half
  or less that of OpenAI's models.
- The OpenAI API (and compatible ones) do not expose a number of
  capabilities that local models have.
- The `ingest` command (from command line or within the chat) can't be
  used concurrently - one instance will overwrite the changes of
  another.

### Roadmap
- You can grep the codebase for "TODO:" tags; these will migrate to github issues
- Document recollection from the store is rather fragmented. It may be
  better to use similarity search just as a signpost to the original
  document, then summarize the document as context.
- Reconsider store document size, since summarization works well
- Define tools for freeform memory access rather than /command syntax
- Define JSON API templates for other web tools
- Self-chat between bots with intention/task injection; see e.g. operand/agency
- Use of tools (see tools.hy)
- Task planning? (see tasks.hy)
