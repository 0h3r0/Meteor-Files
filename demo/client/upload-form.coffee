Template.uploadForm.onCreated ->
  self             = @
  @error           = new ReactiveVar false
  @uploadQTY       = 0
  @showSettings    = new ReactiveVar false
  @showProjectInfo = new ReactiveVar false

  @initiateUpload = (event, files) ->
    unless files.length
      self.error.set "Please select a file to upload"
      return false

    if files.length > 6
      self.error.set "Please select up to 6 files"
      return

    self.uploadQTY = files.length

    cleanUploaded = (current) ->
      _uploads = _.clone _app.uploads.get()
      if _.isArray _uploads
        _.each _uploads, (upInst, index) ->
          if upInst.file.name is current.file.name
            _uploads.splice index, 1
            if _uploads.length
              _app.uploads.set _uploads
            else
              self.uploadQTY = 0
              _app.uploads.set false
          return
      return

    uploads    = []
    transport  = ClientStorage.get 'uploadTransport'
    created_at = +new Date
    _.each files, (file) ->
      Collections.files.insert(
        file: file
        meta: 
          expireAt: new Date(created_at + _app.storeTTL)
          created_at: created_at
          downloads: 0
          blamed: 0
        streams: 'dynamic'
        chunkSize: 'dynamic'
        transport: transport
      ,
        false # Use manual start, so we can attach event listeners
      ).on('end', (error, fileObj) ->
        if not error and files.length is 1
          # Redirect to uploaded file
          # Only then we upload one file
          FlowRouter.go('file', _id: fileObj._id)
        cleanUploaded @
        return
      ).on('abort', ->
        cleanUploaded @
        return
      ).on('error', (error) ->
        self.error.set error?.reason or error
        Meteor.setTimeout ->
          self.error.set false
        , 5000
        cleanUploaded @
        return
      ).on('start', ->
        uploads.push @
        _app.uploads.set uploads
        return
      ).start()

Template.uploadForm.helpers
  error:   -> Template.instance().error.get()
  uploads: -> _app.uploads.get()
  status:  ->
    i                = 0
    uploads          = _app.uploads.get()
    progress         = 0
    uploadQTY        = Template.instance().uploadQTY
    estimateBitrate  = 0
    estimateDuration = 0
    onPause          = false
    if uploads
      for upload in uploads
        onPause           = upload.onPause.get()
        progress         += upload.progress.get()
        estimateBitrate  += upload.estimateSpeed.get()
        estimateDuration += upload.estimateTime.get()
        i++

      if i < uploadQTY
        progress += 100 * (uploadQTY - i)

      progress         = Math.ceil(progress / uploadQTY)
      estimateBitrate  = filesize(Math.ceil(estimateBitrate / i), {bits: true}) + '/s'
      estimateDuration = do ->
        duration = moment.duration Math.ceil(estimateDuration / i)
        hours    = "#{duration.hours()}"
        hours    = "0" + hours if hours.length <= 1
        minutes  = "#{duration.minutes()}"
        minutes  = "0" + minutes if minutes.length <= 1
        seconds  = "#{duration.seconds()}"
        seconds  = "0" + seconds if seconds.length <= 1
        return "#{hours}:#{minutes}:#{seconds}"
    return {progress, estimateBitrate, estimateDuration, onPause}
  showSettings:    -> Template.instance().showSettings.get()
  showProjectInfo: -> Template.instance().showProjectInfo.get()
  uploadTransport: -> ClientStorage.get 'uploadTransport'

Template.uploadForm.events
  'click input[type="radio"]': (e, template) ->
    ClientStorage.set 'uploadTransport', e.currentTarget.value
    true
  'click #pause': (e, template) ->
    e.preventDefault()
    uploads = _app.uploads.get()
    if uploads
      for upload in uploads
        upload.pause()
    false
  'click #abort': (e, template) ->
    e.preventDefault()
    uploads = _app.uploads.get()
    if uploads
      for upload in uploads
        upload.abort()
    false
  'click #continue': (e, template) ->
    e.preventDefault()
    uploads = _app.uploads.get()
    if uploads
      for upload in uploads
        upload.continue()
    false
  'click #fakeUpload': (e, template) ->
    template.$('#userfile').click()
    return
  'dragenter #uploadFile, dragstart #uploadFile': (e, template) ->
    $('#uploadFile').addClass 'file-over'
    return
  'dragleave #uploadFile, dragend #uploadFile': (e, template) ->
    $('#uploadFile').removeClass 'file-over'
    return
  'dragover #uploadFile': (e, template) ->
    e.preventDefault()
    $('#uploadFile').addClass 'file-over'
    e.originalEvent.dataTransfer.dropEffect = 'copy'
    return
  'drop #uploadFile': (e, template) ->
    e.preventDefault()
    template.error.set false
    $('#uploadFile').removeClass 'file-over'
    template.initiateUpload e, e.originalEvent.dataTransfer.files, template
    false
  'change input[name="userfile"]': (e, template) -> template.$('form#uploadFile').submit()
  'submit form#uploadFile': (e, template) ->
    e.preventDefault()
    template.error.set false
    template.initiateUpload e, e.currentTarget.userfile.files
    false
  'click #showSettings': (e, template) ->
    e.preventDefault()
    $('.gh-ribbon').toggle()
    template.showSettings.set !template.showSettings.get()
    false
  'click #showProjectInfo': (e, template) ->
    e.preventDefault()
    $('.gh-ribbon').toggle()
    template.showProjectInfo.set !template.showProjectInfo.get()
    false