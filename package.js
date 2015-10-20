Package.describe({
  name: 'ostrio:files',
  version: '1.3.10',
  summary: 'Upload, Store and Stream (Video & Audio streaming) files to/from file system (FS) via DDP and HTTP',
  git: 'https://github.com/VeliovGroup/Meteor-Files',
  documentation: 'README.md'
});

Package.onUse(function(api) {
  api.versionsFrom('1.1');
  api.addFiles('files.coffee');
  api.use(['templating', 'reactive-var', 'tracker'], 'client');
  api.use(['underscore', 'check', 'sha', 'ostrio:cookies@2.0.1', 'random', 'coffeescript', 'iron:router@1.0.12', 'aldeed:collection2@2.5.0'], ['client', 'server']);
});

Npm.depends({
  'fs-extra': '0.22.1',
  'file-type': '2.10.2',
  'request': '2.58.0'
});