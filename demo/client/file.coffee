Template.file.onCreated ->
  @fetchedText = new ReactiveVar false
  @warning = new ReactiveVar false

Template.file.onRendered ->
  @warning.set false
  @fetchedText.set false
  if @data.file.isText or @data.file.isJSON
    self = @
    HTTP.call 'GET', Collections.files.link(@data.file), (error, resp) ->
      if error
        console.error error
      else
        if !~[500, 404, 400].indexOf resp.statusCode
          if resp.content.length < 1024 * 64
            self.fetchedText.set resp.content
          else
            self.warning.set 'File too big to show, please download.'

Template.file.helpers
  fetchedText: -> Template.instance().fetchedText.get()
  warning: -> Template.instance().warning.get()
  getCode: -> if @type and !!~@type.indexOf('/') then @type.split('/')[1] else ''