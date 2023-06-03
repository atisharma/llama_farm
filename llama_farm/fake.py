from itertools import cycle

from langchain.chat_models.base import SimpleChatModel

    
class ChatFakeList(SimpleChatModel):
  "Chat model class that gives fixed response."

  response = "You need to specify a valid language model 'kind = ...' in the config.",

  @property
  def _llm_type(self):
    return "fake"

  def _call(self, * args, ** kwags):
    "Chat model class that gives fixed response."
    return self.response
    
