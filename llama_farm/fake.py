from itertools import cycle

from langchain.chat_models.base import SimpleChatModel

    
class ChatFakeList(SimpleChatModel):
  "Chat model class that cycles over responses."

  response = "You need to specify a valid language model 'kind = ...' in the config.",

  @property
  def _llm_type(self):
    return "fake"

  def _call(self, * args, ** kwags):
    "Chat model class that cycles over responses."
    return self.response
    
