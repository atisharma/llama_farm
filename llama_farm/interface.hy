"
Functions that relate to output on the screen.
"

(require hyrule.argmove [-> ->> as->])

(import hashlib [md5])

(import rich.console [Console])
(import rich.padding [Padding])
(import rich.markdown [Markdown])
(import rich.columns [Columns])
(import rich.table [Table])
(import rich.text [Text])
(import rich.progress [track])
(import rich.color [ANSI_COLOR_NAMES])


(setv console (Console :highlight None))
(setv colors (list (.keys ANSI_COLOR_NAMES)))
(setv render-markdown True)


;;; -----------------------------------------------------------------------------
;;; Screen control
;;; -----------------------------------------------------------------------------

(defn clear []
  (console.clear))
  
(defn set-width [line]
  (try
    (let [arg (get (.partition line " ") 2)]
      (global console)
      (setv console (Console :highlight None :width (int arg))))
    (except [[IndexError ValueError]]
      (error "Bad console width value."))))

(defn get-margin [chat-history]
  "Max over length of bot names, for use in chat formatting."
  (max 1 1 #* (lfor m chat-history (len (:bot m)))))

(defn toggle-markdown []
  "Toggle the rendering of markdown in output."
  (global render-markdown)
  (setv render-markdown (not render-markdown)))

(defn bot-color [bot]
  "The signature color of the bot, derived from its name."
  (let [bot (.capitalize bot)
        i (-> (bot.encode "utf-8")
              (md5)
              (.hexdigest)
              (int 16)
              (% 222)
              (+ 1))]
    (get colors i)))

(defn spinner-context [s [style "italic green"] [spinner "dots12"]]
  (console.status (Text s :style style)
                  :spinner spinner))

;;; -----------------------------------------------------------------------------
;;; Printers
;;; -----------------------------------------------------------------------------

(defn banner []
  (console.clear)
  (setv banner-text r"  _ _                             ___                   :
 | | |                           / __)                  :
 | | | _____ ____  _____ _____ _| |__ _____  ____ ____  :
 | | |(____ |    \(____ (_____|_   __|____ |/ ___)    \ :
 | | |/ ___ | | | / ___ |       | |  / ___ | |   | | | |:
  \_)_)_____|_|_|_\_____|       |_|  \_____|_|   |_|_|_|:
 :")
  (lfor [l c] (zip (.split banner-text ":")
                   ["#11FF00" "#33DD00" "#33BB00" "#339900" "#337720" "#227799" "#2288FF" "#2288FF"])
        (console.print l
                       :end None
                       :style f"bold {c}"
                       :overflow "crop"))
  (console.print "[default]"))

(defn print-chat-history [chat-history [tokens None]]
  "Format and print the chat history to the console."
  (let [margin (get-margin chat-history)]
    (console.rule)
    (if tokens
      (console.print f"Chat history (~ {tokens} tokens):" :style "green italic")
      (console.print "Chat history:" :style "green italic"))
    (console.print)
    (for [msg chat-history]
      (print-message msg margin :padding #(0 4 0 0)))
    (console.rule)))

(defn print-markdown [s [style None] [padding #(0 3 0 0)]]
  "Print some markdown to the screen."
  (-> s
      (sanitize-markdown)
      (Markdown)
      (Padding padding)
      (console.print :justify "left" :style style)))

(defn info [s [style "green italic"]]
  "Print an information string to the screen."
  (print-markdown s :style style))

(defn error [s [style "red italic"]]
  "Print an error string to the screen."
  (print-markdown s :style style))

(defn status-line [s]
  "Print a status line at the bottom of the screen."
  ;(print "\033[s" :end "") ; save cursor position
  ;(print "\033[u" :end "") ; restore cursor position
  ;(print) ; move on one line
  (print) ; move on one line
  (console.rule)
  ; cropping not working :(
  (let [max-length-s (+ console.width 24)
        one-line-s (.replace s "\n" "; ")
        truncated-s (if (> (len one-line-s) max-length-s)
                        (+ (cut one-line-s 0 max-length-s) "…")
                        s)]
    (console.print truncated-s
                   :end "\r"
                   :overflow "ellipsis"
                   :crop True))
  (for [n (range (+ 2 (.count s "\n")))]
    (print "\033[1A" :end "")) ; up one line
  (print "\033[K" :end "")) ; clear to end of line for new input
  
(defn clear-status-line []
  "Hack to avoid old status line polluting new output."
  (print "\033[K" :end "") ; clear to end of line
  (print)
  (print "\033[K" :end "") ; clear to end of line
  (print)
  (print "\033[K" :end "") ; clear to end of line
  (print)
  (print "\033[1A" :end "") ; up one line
  (print "\033[1A" :end "") ; up one line
  (print "\033[1A" :end "")) ; up one line
  
(defn exception []
  "Formats and prints the current exception."
  (console.print-exception))

(defn print-message [msg margin [padding #(0 1 0 0)]]
  "Format and print a message to the screen."
  (let [bot (.capitalize (:bot msg))
        color (bot-color bot)
        output (Table :padding padding
                      :expand True
                      :show-header False
                      :show-lines False
                      :box None)]
    (.add-column output :min-width margin)
    (.add-column output :ratio 1 :overflow "fold")
    (.add-row output f"[bold {color}]{bot}:[/bold {color}]"
              (if render-markdown
                  (Markdown (sanitize-markdown (:content msg)))
                  (:content msg)))
    (console.print output :justify "left")))

(defn print-last-message [chat-history margin]
  (-> chat-history
    (get -1)
    (print-message margin)))

(defn print-sources [docs]
  "Print relevant document metadata from a list of docs."
  (print-markdown
    (.join "\n"
           (lfor d docs
                 (let [page f"{(:page d.metadata "")}"
                       source (:source d.metadata "unknown source")]
                   (+ " - " source (if page f" (p{page})" "")))))
    :style "green italic")
  (console.rule))

(defn print-docs [docs]
  "Print a list of docs."
  (console.rule)
  (for [d docs]
    (print-markdown (format-metadata d)
                    :style "bold green italic")
    (print-markdown d.page-content
                    :padding #(0 4 1 4)))
  (console.rule))

(defn tabulate [rows headers
                [styles None]
                [title None]]
  "Print a rich table object from a list of lists (rows) and a list (headers)."
  (let [table (Table :title title :row-styles styles)]
    (for [h headers]
      (.add-column table h))
    (for [r rows]
      (.add-row table #* r))
    (console.print table :style "green")))

;;; -----------------------------------------------------------------------------
;;; Formatters
;;; -----------------------------------------------------------------------------

(defn sanitize-markdown [s]
  "Prepare a generic string for markdown rendering."
  ;; Markdown swallows single newlines.
  ;; and defines the antipattern of preserving them with a double space.
  (.replace s "\n" "  \n"))

(defn format-msg [message margin]
  "Format a chat message for display."
  (let [l (-> message
              (:bot)
              (.capitalize)
              (+ ":"))
        content (-> message
                    (:content)
                    (.strip))]
                    ;(.replace "\n" "\n\n"))]
    f"{l :<{(+ 1 margin)}} {(.strip (:content message))}"))

(defn format-metadata [doc]
  "Format a single document's metadata (as a list) for display as a string."
  (let [source (:source doc.metadata "")
        topic (:topic doc.metadata "")
        time (:topic doc.metadata "")
        metadata (filter None [source topic time])]
    (.join "\n" metadata)))
  
(defn format-source [doc]
  "Format a single document's source for display as a string."
  (let [page (str (:page doc.metadata ""))]
    (+ "- "
       (:source doc.metadata "unknown source")
       (if page f" (p{page})" ""))))

(defn format-sources [docs]
  "Format documents' sources (only) as a string."
  (.join "\n"
         (sfor d docs
               (format-source d))))
              
(defn format-response-with-sources [response]
  "Format a response with sources as a string."
  (.join "\n"
    [(:result response)
     "\n"
     #* (sfor d (:source-documents response)
              (format-source d))]))
          
