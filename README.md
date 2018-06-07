# telegram-bot-microframework-perl

What it allows to do:
 - Respond to predeclared messages (can be defined by patterns)
 - Build menus with few messages in a row (see Plugin::Telegram::Operation)
 
What it should do:
 - Inline queries support
 - Authentication
 

Wrapping BotAPI to simplify new bots development

Uses AnyEvent for asynchronous networking.

Wrapper allows you to build your own bot simply defining responses to commands,
but also can help you with more complicated scenarios (operations including few messages, authentication)
