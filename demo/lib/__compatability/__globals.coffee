@Collections = {}
@_app = 
  subs: new SubsManager()
  storeTTL: 259200000
  NOOP: -> return

if Meteor.isClient
  ClientStorage.set('uploadTransport', 'ddp') unless ClientStorage.has 'uploadTransport'
  Template.registerHelper 'filesize', (size = 0) -> filesize size
  Template.registerHelper 'extless', (filename = '') ->
    parts = filename.split '.'
    parts.pop() if parts.length > 1
    return parts.join '.'

  marked.setOptions
    highlight: (code) ->  hljs.highlightAuto(code).value
    renderer: new marked.Renderer()
    gfm: true
    tables: true
    breaks: false
    pedantic: false
    sanitize: true
    smartLists: true
    smartypants: false