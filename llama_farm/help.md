To chat, just enter some text.

Lines beginning with **/** are parsed as commands.  
The usual readline shortcuts should be available.

### REPL

- **/help /h**                      Show this helpful text
- **/quit /q /exit**                Quit
- **/quit!**                        Quit without saving the conversation
- **/version**                      Show the version of this client
- **/clear**                        Clear the display
- **/markdown**                     Toggle markdown rendering of messages

### Bots

- **/bots**                         List the available bots
- **/bot /b**                       Show the current bot to whom input goes
- **/bot 'name'**                   Start talking to a particular bot

### Conversation

- **/undo**                         Delete the last two items in the conversation
- **/retry**                        Get a new response to the last input
- **/history**                      Print the whole chat history for this session
- **/reset!**                       Discard the whole current chat history

### Memory

- **/topic 'new topic'**            Manually set a topic
- **/topic**                        Set a topic from the discussion
- **/context**                      Set and show the current context 

- **/sources 'query'**              Search the knowledge store for relevant sources (MMR search)
- **/similarity 'query'**           Search the knowledge store for relevant information (similarity search)
- **/recall 'query'**               Make a query against the long-term chat memory (summary)
- **/know 'query'**                 Make a query against the knowledge store (summary)

### Chat-aware query

- **/ask 'query'**                  Ask a question over the knowledge store
- **/wikipedia 'query'**            Ask a question with reference to wikipedia
- **/arxiv 'query'**                Ask a question with access to arXiv
- **/youtube 'youtube-id' 'query'** Ask a question about a youtube transcript
- **/url 'url 'query'**             Ask a question about a web page

### Summarize external sources

- **/summ-youtube 'youtube-id'**      Summarize a Youtube video
- **/summ-url 'https://example.com'** Summarize example.com

### Knowledge management

- **/ingest 'filename(s)'**         Ingest a filename, list of filenames (separated by spaces, no quotes), or directory (recursively) to the knowledge store  
- **/ingest 'urls(s)'**             Ingest a webpage at a single url or list of urls (separated by spaces, no quotes)
