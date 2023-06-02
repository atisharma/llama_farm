To chat, just enter some text.

Lines beginning with **/** are parsed as commands.  
The usual readline shortcuts should be available.

### REPL

- **/help /h**                   Show this helpful text
- **/quit /q /exit**             Quit
- **/quit!**                     Quit without saving the conversation
- **/version**                   Show the version of this client
- **/clear**                     Clear the display
- **/markdown**                  Toggle markdown rendering of messages

### Bots

- **/bots**                      List the available bots
- **/bot /b**                    Show the current bot to whom input goes
- **/bot 'name'**                Start talking to a particular bot

### Conversation

- **/undo**                      Delete the last two items in the conversation
- **/retry**                     Get a new response to the last input
- **/history**                   Print the whole chat history for this session
- **/reset!**                    Discard the whole current chat history

### Chat-context query

- **/wikipedia 'query'**         Ask the bot a question with reference to wikipedia
- **/arxiv 'query'**             Ask the bot a question with access to arXiv
- **/ask 'query'**               Ask the bot a question over the knowledge store

### Memory

- **/context**                   Reset and show the current context (in case the topic changed quickly)
- **/topic**                     Show the current topic
- **/topic 'new topic'**         Manually set the current topic

- **/sources 'query'**           Directly search the vectorstore for relevant sources (MMR search)
- **/similarity 'query'**        Directly search the vectorstore for relevant information (similarity search)
- **/recall 'query'**            Make a query against the bot's long-term chat memory (summary)
- **/know 'query'**              Make a query against the bot's knowledge store (summary)

### Summarize external sources

- **/youtube 'youtube-id'**      Summarize a Youtube video
- **/url 'https://example.com'** Summarize example.com

### Knowledge management

- **/ingest 'filename(s)'**      Ingest a filename, list of filenames (separated by spaces, no quotes), or directory (recursively) to the knowledge store  
- **/ingest 'urls(s)'**          Ingest a webpage at a single url or list of urls (separated by spaces, no quotes)
