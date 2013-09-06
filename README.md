# KoLIRC

Connect to Kingdom of Loathing chat from an IRC client.

Still in early development but does work for basic channels.

## To use

To get the daemon running:

    $ git clone https://github.com/coderanger/kolirc.git
    $ cd kolirc
    $ npm install
    $ npm start

Then configure your IRC client to connect to `localhost:2345` using your KoL
username as the nickname and with your KoL password as the server password (not
Nickserv or similar, actual server password).

## A note about password safety

While kolirc goes as far as it can to protect your password, IRC itself does
transmit in cleartext, so it is currently inadvisable to use run kolirc on an
external server unless you trust the network between your IRC client and kolirc.
In the future kolirc will add SSL support to reduce this issue.
