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
- **/bot name**                  Start talking to a particular bot

### Conversation

- **/undo**                      Delete the last two items in the conversation
- **/retry**                     Get a new response to the last input
- **/history**                   Print the whole chat history for this session
- **/reset!**                    Discard the whole current chat history

### Memory

- **/topic new topic**           Manually set a topic
- **/topic**                     Set a topic from the discussion
- **/context**                   Set and show the current context 

- **/sources query**             Search the knowledge store for relevant sources (MMR search)
- **/similarity query**          Search the knowledge store for relevant information (similarity search)
- **/recall query**              Make a query against the long-term chat memory (summary)
- **/know query**                Make a query against the knowledge store (summary)

### Chat-aware query

- **/ask query**                 Chat over the knowledge store and chat memory
- **/wikipedia query**           Chat with reference to wikipedia
- **/youtube youtube-id query**  Chat over a youtube transcript
- **/url url query**             Chat over a web page
- **/file filename query**       Chat over a text file

### Summarize external sources

- **/summ-youtube youtube-id**      Summarize a Youtube video
- **/summ-url https://example.com** Summarize example.com
- **/summ-file filename**           Summarize a text file

### Knowledge management

- **/ingest filename**           Ingest a filename, list of filenames, or directory (recursively)
- **/ingest "f1" "f2" "dir3"**   (quoting as necessary)
- **/ingest urls(s)**            Ingest a webpage at a single url or list of urls (separated by spaces, no quotes)
