#!/usr/bin/env node
require('coffee-script-mapped');
Server = require('../lib/server');
new Server(2345);
