if Meteor.isServer
  ###
  @description Require "fs-extra" npm package
  ###
  fs      = Npm.require "fs-extra"
  request = Npm.require "request"

  ###
  @var {object} bound - Meteor.bindEnvironment aka Fiber wrapper
  ###
  bound = Meteor.bindEnvironment (callback) ->
    return callback()

###
@object
@name _insts
@description Object of Meteor.Files instances
###
_insts = {}

###
@function
@name rcp
@param {Object} obj - Initial object
@description Create object with only needed props
###
rcp = (obj) ->
  o =
    currentFile:    obj.currentFile
    search:         obj.search
    storagePath:    obj.storagePath
    collectionName: obj.collectionName
    downloadRoute:  obj.downloadRoute
    chunkSize:      obj.chunkSize
    debug:          obj.debug
    _prefix:        obj._prefix
    cacheControl:   obj.cacheControl
    versions:       obj.versions
  return o

###
@function
@name cp
@param {Object} to   - Destanation
@param {Object} from - Source
@description Copy-Paste only needed props from one to another object
###
cp = (to, from) ->
  to.currentFile    = from.currentFile
  to.search         = from.search
  to.storagePath    = from.storagePath
  to.collectionName = from.collectionName
  to.downloadRoute  = from.downloadRoute
  to.chunkSize      = from.chunkSize
  to.debug          = from.debug
  to._prefix        = from._prefix
  to.cacheControl   = from.cacheControl
  to.versions       = from.versions
  return to

###
@class
@namespace Meteor
@name Files
@param {Object} config - Configuration object with next properties:
  {String}    storagePath     - Storage path on file system
  {String}    collectionName  - Collection name
  {String}    downloadRoute   - Server Route used to retrieve files
  {Object}    schema          - Collection Schema
  {Number}    chunkSize       - Upload chunk size
  {Function}  namingFunction  - Function which returns `String`
  {Boolean}   debug           - Turn on/of debugging and extra logging
  {Boolean}   allowClientCode - Allow to run `remove` from client
  {String|Function} onbeforeunloadMessage - Message shown to user when closing browser's window or tab while upload process is running
@description Create new instance of Meteor.Files
###
class Meteor.Files
  constructor: (config) ->
    {@storagePath, @collectionName, @downloadRoute, @schema, @chunkSize, @namingFunction, @debug, @onbeforeunloadMessage, @permissions, @allowClientCode, @integrityCheck, @protected, @public, @strict} = config if config

    @collectionName   = 'MeteorUploadFiles' if not @collectionName
    @chunkSize        = 272144 if not @chunkSize
    @namingFunction   = String.rand if not @namingFunction
    @debug            = false if not @debug
    @permissions      = 0o777 if not @permissions
    @allowClientCode  = true if not @allowClientCode
    @integrityCheck   = true if not @integrityCheck
    @protected        = false if not @protected
    @public           = false if not @public
    @strict           = false if not @strict
    @onbeforeunloadMessage = 'Upload in a progress... Do you want to abort?' if not @onbeforeunloadMessage
    
    if @public and @storagePath
      @downloadRoute  = if @storagePath.indexOf('/') isnt 1 then "/uploads/#{@storagePath}" else "/uploads#{@storagePath}"
      @storagePath    = if @storagePath.indexOf('/') isnt 1 then "../web.browser/app/#{@storagePath}" else "../web.browser/app#{@storagePath}"

    if not @storagePath
      @storagePath    = if @public then "../web.browser/app/uploads/#{@collectionName}" else "/assets/app/uploads/#{@collectionName}"
      @downloadRoute  = if @public then "/uploads/#{@collectionName}" else '/cdn/storage' if not @downloadRoute
    
    if not @downloadRoute
      @downloadRoute  = '/cdn/storage'


    if not @schema
      @schema = 
        name:
          type: String
        type:
          type: String
        extension:
          type: String
        path:
          type: String
        meta:
          type: Object
          blackbox: true
          optional: true
        userId:
          type: String
          optional: true
        versions:
          type: Object
          blackbox: true
        isVideo:
          type: Boolean
        isAudio:
          type: Boolean
        isImage:
          type: Boolean
        size:
          type: Number
        _prefix:
          type: String
        _collectionName:
          type: String
        _storagePath:
          type: String
        _downloadRoute:
          type: String

    check @storagePath, String
    check @collectionName, String
    check @downloadRoute, String
    check @chunkSize, Number
    check @namingFunction, Function
    check @allowClientCode, Boolean
    check @debug, Boolean
    check @onbeforeunloadMessage, Match.OneOf String, Function
    check @integrityCheck, Boolean
    check @public, Boolean
    check @protected, Match.OneOf Boolean, Function

    if @public and @protected
      throw new Meteor.Error 500, "[Meteor.File.#{@collectionName}]: Files can not be public and protected at the same time!"
    
    @storagePath    = @storagePath.replace /\/$/, ''
    @downloadRoute  = @downloadRoute.replace /\/$/, ''
    @collection     = new Mongo.Collection @collectionName

    self          = @
    @currentFile  = null
    @cursor       = null
    @search       = {}
    @cacheControl = 'public, max-age=31536000'


    @collection.attachSchema @schema

    @collection.deny
      insert: ->
        true
      update: ->
        true
      remove: ->
        true
    
    @_prefix = SHA256 @collectionName + @storagePath + @downloadRoute
    _insts[@_prefix] = @

    @checkAccess = (http) ->
      if @protected
        user = false

        if Meteor.isServer
          if _.has(Package, 'accounts-base') and Meteor.cookie.has 'meteor_login_token'
            user = Meteor.users.findOne
              "services.resume.loginTokens.hashedToken": Accounts._hashLoginToken Meteor.cookie.get 'meteor_login_token'
            func = 
              user: () ->
                return user
              userId: user._id
          else
            func = 
              user: () ->
                return undefined
              userId: undefined
        else
          if _.has(Package, 'accounts-base') and Meteor.userId() 
            user = Meteor.user()
            func = 
              user: () ->
                return Meteor.user()
              userId: Meteor.userId()
          else
            func = 
              user: () ->
                return undefined
              userId: undefined

        if _.isFunction @protected
          result = if http then @protected.call(_.extend(http, func)) else @protected.call func
        else
          result = !!user

        if http and not result
          console.warn "Access denied!" if @debug
          if http
            text = "Access denied!"
            http.response.writeHead 401,
              'Content-Length': text.length
              'Content-Type':   "text/plain"
            http.response.end text
          return false
        else
          return true
      else
        return true

    if not @public
      Router.route "#{@downloadRoute}/#{@collectionName}/:_id/:version/:name", ->
        self.findOne(@params._id).download.call(self, @, @params.version) if self.checkAccess @
      , {where: 'server'}
    else
      Router.route "#{@downloadRoute}/:file", ->
        if @params.file.indexOf('-') isnt -1
          version = @params.file.split('-')[0]
        else
          version = 'original'

        self.download.call self, @, version
      , {where: 'server'}

    @methodNames =
      MeteorFileWrite:  "MeteorFileWrite#{@_prefix}"
      MeteorFileUnlink: "MeteorFileUnlink#{@_prefix}"

    if Meteor.isServer
      _methods = {}

      _methods[self.methodNames.MeteorFileUnlink] = (inst) ->
        check inst, Object
        console.info "Meteor.Files Debugger: [MeteorFileUnlink]" if self.debug
        if self.allowClientCode
          self.remove.call cp(_insts[inst._prefix], inst), inst.search
        else
          throw new Meteor.Error 401, '[Meteor.Files] [remove()] Run code from client is not allowed!'

      _methods[self.methodNames.MeteorFileWrite] = (unitArray, fileData, meta, first, chunksQty, currentChunk, totalSentChunks, randFileName, part, partsQty, fileSize) ->
        console.info "Meteor.Files Debugger: [MeteorFileWrite] {name: #{randFileName}, meta:#{meta}}" if self.debug
        check unitArray, Match.OneOf Uint8Array, Object
        check fileData, Object
        check meta, Match.Optional Object
        check first, Boolean
        check chunksQty, Number
        check currentChunk, Number
        check totalSentChunks, Number
        check randFileName, String
        check part, Number
        check partsQty, Number
        check fileSize, Number

        console.info "Meteor.Files Debugger: Received chunk ##{currentChunk} of #{chunksQty} chunks, in part: #{part}, file: #{fileData.name or fileData.fileName}" if self.debug

        i = 0
        binary = ''
        while i < unitArray.byteLength
          binary += String.fromCharCode unitArray[i]
          i++
        last   = (chunksQty * partsQty <= totalSentChunks)

        cleanName = (str) ->
          str.replace(/\.\./g, '').replace /\//g, ''

        fileName  = cleanName(fileData.name or fileData.fileName)
        ext       = fileName.split('.').pop()
        pathName  = "#{self.storagePath}/#{randFileName}"
        path      = "#{self.storagePath}/#{randFileName}.#{ext}"
        pathPart  = if partsQty > 1 then "#{self.storagePath}/#{randFileName}_#{part}.#{ext}" else path
        result    = 
          name:       fileName
          extension:  ext
          path:       path
          meta:       meta
          type:       fileData.type
          size:       fileData.size
          chunk:      currentChunk
          versions:
            original:
              path: path
              size: fileData.size
              type: fileData.type
              extension: ext
          last:       last
          isVideo:    fileData.type.toLowerCase().indexOf("video") > -1
          isAudio:    fileData.type.toLowerCase().indexOf("audio") > -1
          isImage:    fileData.type.toLowerCase().indexOf("image") > -1
          _prefix:    self._prefix
          _collectionName: self.collectionName
          _storagePath:    self.storagePath
          _downloadRoute:  self.downloadRoute

        
        if first
          fs.outputFileSync pathPart, binary, 'binary'
        else
          fs.appendFileSync pathPart, binary, 'binary'

        if (chunksQty is currentChunk) and self.debug
          console.info "Meteor.Files Debugger: The part ##{part} of file #{fileName} (binary) was saved to #{pathPart}"

        if last
          if partsQty > 1
            buffers = []
            i = 2
            while i <= partsQty
              fs.appendFileSync pathName + '_1.' + ext, fs.readFileSync(pathName + '_' + i + '.' + ext), 'binary'
              fs.unlink pathName + '_' + i + '.' + ext
              i++
            fs.renameSync pathName + '_1.' + ext, path

          fs.chmod path, self.permissions
          result._id = self.collection.insert _.clone result

          console.info "Meteor.Files Debugger: The file #{fileName} (binary) was saved to #{path}" if self.debug
        return result

      Meteor.methods _methods

  srch: (search) ->
    if search and _.isString search
      @search =
        _id: search
    else
      @search = search

    @search

  ###
  @server
  @function
  @class Meteor.Files
  @name write
  @param {Buffer} buffer - Binary File's Buffer
  @param {Object} opts - {fileName: '', type: '', size: 0, meta: {...}}
  @param {Function} callback - function(error, fileObj){...}
  @description Write buffer to FS and add to Meteor.Files Collection
  @returns {Files} - Return this
  ###
  write: if Meteor.isServer then (buffer, opts = {}, callback) ->
    console.info "Meteor.Files Debugger: [write(buffer, #{opts}, callback)]" if @debug
    check opts, Match.Optional Object
    check callback, Match.Optional Function

    if @checkAccess()
      randFileName  = @namingFunction.call null, true
      fileName      = if opts.name or opts.fileName then opts.name or opts.fileName else randFileName
      extension     = fileName.split('.').pop()
      path          = "#{@storagePath}/#{randFileName}.#{extension}"
      
      opts.type = 'application/*' if not opts.type
      opts.meta = {} if not opts.meta
      opts.size = buffer.length if not opts.size

      result = 
        name:       fileName
        extension:  extension
        path:       path
        meta:       opts.meta
        type:       opts.type
        size:       opts.size
        isVideo: if opts.type then opts.type.toLowerCase().indexOf("video") > -1 else false
        isAudio: if opts.type then opts.type.toLowerCase().indexOf("audio") > -1 else false
        isImage: if opts.type then opts.type.toLowerCase().indexOf("image") > -1 else false
        versions:
          original:
            path: path
            type: opts.type
            size: opts.size
            extension: extension
        _prefix: @_prefix
        _collectionName: @collectionName
        _storagePath:    @storagePath
        _downloadRoute:  @downloadRoute

      console.info "Meteor.Files Debugger: The file #{fileName} (binary) was added to #{@collectionName}" if @debug

      if callback
        fs.outputFile path, buffer, 'binary', callback
      else
        fs.outputFileSync path, buffer, 'binary'

      result._id = @collection.insert _.clone result

      callback and callback null, result
      return result
  else
    undefined

  ###
  @server
  @function
  @class Meteor.Files
  @name load
  @param {String} url - URL to file
  @param {Object} opts - {fileName: '', meta: {...}}
  @param {Function} callback - function(error, fileObj){...}
  @description Download file, write stream to FS and add to Meteor.Files Collection
  @returns {Files} - Return this
  ###
  load: if Meteor.isServer then (url, opts = {}, callback) ->
    console.info "Meteor.Files Debugger: [load(#{url}, #{opts}, callback)]" if @debug
    check url, String
    check opts, Match.Optional Object
    check callback, Match.Optional Function

    self = @
    if @checkAccess()
      randFileName  = @namingFunction.call null, true
      fileName      = if opts.name or opts.fileName then opts.name or opts.fileName else randFileName
      extension     = fileName.split('.').pop()
      path          = "#{@storagePath}/#{randFileName}.#{extension}"
      opts.meta     = {} if not opts.meta

      request.get(url).on('error', (error)->
        throw new Meteor.Error 500, "Error on [load(#{url}, #{opts})]; Error:" + JSON.stringify error
      ).on('response', (response) ->
        bound ->
          result = 
            name:       fileName
            extension:  extension
            path:       path
            meta:       opts.meta
            type:       response.headers['content-type']
            size:       response.headers['content-length']
            isVideo: response.headers['content-type'].toLowerCase().indexOf("video") > -1
            isAudio: response.headers['content-type'].toLowerCase().indexOf("audio") > -1
            isImage: response.headers['content-type'].toLowerCase().indexOf("image") > -1
            versions:
              original:
                path: path
                type: response.headers['content-type']
                size: response.headers['content-length']
                extension: extension
            _prefix: self._prefix
            _collectionName: self.collectionName
            _storagePath:    self.storagePath
            _downloadRoute:  self.downloadRoute

          console.info "Meteor.Files Debugger: The file #{fileName} (binary) was loaded to #{@collectionName}" if @debug

          result._id = self.collection.insert _.clone result
          callback and callback null, result

      ).pipe fs.createOutputStream path

  else
    undefined

  ###
  @server
  @function
  @class Meteor.Files
  @name addFile
  @param {String} path - Path to file
  @param {String} path - Path to file
  @description Add file from FS to Meteor.Files
  @returns {Files} - Return this
  ###
  addFile: if Meteor.isServer then (path, opts, callback) ->
    console.info "[addFile(#{path})]" if @debug

    throw new Meteor.Error 403, "Can not run [addFile()] on public collection" if @public
    check path, String
    check opts, Match.Optional Object
    check callback, Match.Optional Function

    try
      stats     = fs.statSync path

      if stat.isFile()
        fileSize  = stats.size
        pathParts = path.split '/'
        fileName  = pathParts[pathParts.length - 1]
        ext       = fileName.split('.').pop()

        opts.type = 'application/*' if not opts.type
        opts.meta = {} if not opts.meta
        opts.size = fileSize if not opts.size

        result    = 
          name:       fileName
          extension:  ext
          path:       path
          meta:       opts.meta
          type:       opts.type
          size:       opts.size
          isVideo:    opts.type.toLowerCase().indexOf("video") > -1
          isAudio:    opts.type.toLowerCase().indexOf("audio") > -1
          isImage:    opts.type.toLowerCase().indexOf("image") > -1
          versions:
            original:
              path: path
              type: opts.type
              size: opts.size
              extension: ext
          _prefix:         @_prefix
          _collectionName: @collectionName
          _storagePath:    path.replace "/#{fileName}", ''
          _downloadRoute:  @downloadRoute

        result._id = @collection.insert _.clone result
        console.info "The file #{fileName} (binary) was added to #{@collectionName}" if @debug

        callback and callback null, result
        return result
      else
        error = new Meteor.Error 400, "[Files.addFile(#{path})]: File does not exist"
        callback and callback error
        return error

    catch error
      callback and callback error
      return error
  else
    undefined

  ###
  @isomorphic
  @function
  @class Meteor.Files
  @name findOne
  @param {String|Object} search - `_id` of the file or `Object` like, {prop:'val'}
  @description Load file
  @returns {Files} - Return this
  ###
  findOne: (search) ->
    console.info "Meteor.Files Debugger: [findOne(#{search})]" if @debug
    check search, Match.OneOf Object, String
    @srch search

    if @checkAccess()
      @currentFile = @collection.findOne @search
      @cursor      = null
      return @

  ###
  @isomorphic
  @function
  @class Meteor.Files
  @name find
  @param {String|Object} search - `_id` of the file or `Object` like, {prop:'val'}
  @description Load file or bunch of files
  @returns {Files} - Return this
  ###
  find: (search) ->
    console.info "Meteor.Files Debugger: [find(#{search})]" if @debug
    check search, Match.OneOf Object, String
    @srch search

    if @checkAccess
      @currentFile = null
      @cursor = @collection.find @search
      return @

  ###
  @isomorphic
  @function
  @class Meteor.Files
  @name get
  @description Return value of current cursor or file
  @returns {Object|[Object]}
  ###
  get: () ->
    console.info "Meteor.Files Debugger: [get()]" if @debug
    return @cursor.fetch() if @cursor
    return @currentFile

  ###
  @isomorphic
  @function
  @class Meteor.Files
  @name fetch
  @description Alias for `get()` method
  @returns {[Object]}
  ###
  fetch: () ->
    console.info "Meteor.Files Debugger: [fetch()]" if @debug
    data = @get()
    if not _.isArray data
      return [data]
    else
      data

  ###
  @client
  @function
  @class Meteor.Files
  @name insert
  @param {Object} config - Configuration object with next properties:
    {File|Object} file           - HTML5 `files` item, like in change event: `e.currentTarget.files[0]`
    {Object}      meta           - Additional data as object, use later for search
    {Number}      streams        - Quantity of parallel upload streams
    {Function}    onUploaded     - Callback triggered when upload is finished, with two arguments `error` and `fileRef`
    {Function}    onProgress     - Callback triggered when chunk is sent, with only argument `progress`
    {Function}    onBeforeUpload - Callback triggered right before upload is started, with only `FileReader` argument:
                                   context is `File` - so you are able to check for extension, mime-type, size and etc.
                                   return true to continue
                                   return false to abort upload
  @description Upload file to server over DDP
  @url https://developer.mozilla.org/en-US/docs/Web/API/FileReader
  @returns {Object} with next properties:
    {ReactiveVar} onPause      - Is upload process on the pause?
    {Function}    pause        - Pause upload process
    {Function}    continue     - Continue paused upload process
    {Function}    toggle       - Toggle continue/pause if upload process
  ###
  insert: if Meteor.isClient then (config) ->
    if @checkAccess()
      console.info "Meteor.Files Debugger: [insert()]" if @debug
      {file, meta, onUploaded, onProgress, onBeforeUpload, streams} = config
      check meta, Match.Optional Object
      check onUploaded, Match.Optional Function
      check onProgress, Match.Optional Function
      check onBeforeUpload, Match.Optional Function
      check streams, Match.Optional Number

      if file
        console.time('insert') if @debug
        self    = @
        result  = 
          onPause: new ReactiveVar false
          continueFrom: []
          pause: () ->
            @onPause.set true
          continue: () ->
            @onPause.set false
            for func in @continueFrom
              func.call null
            @continueFrom = []
          toggle: () ->
            if @onPause.get() then @continue() else @pause()
          progress: new ReactiveVar 0

        Tracker.autorun ->
          if Meteor.status().connected
            result.continue()
            console.info "Meteor.Files Debugger: Connection established continue() upload" if self.debug
          else
            result.pause()
            console.info "Meteor.Files Debugger: Connection error set upload on pause()" if self.debug

        streams         = 1 if not streams
        totalSentChunks = 0

        fileData      =
          size: file.size
          type: file.type
          name: file.name
          ext:  file.name.split('.').pop()
          extension: file.name.split('.').pop()

        file          = _.extend file, fileData
        randFileName  = @namingFunction.call null, true
        partSize      = Math.ceil file.size / streams
        parts         = []
        uploaded      = 0
        last          = false

        window.onbeforeunload = (e) ->
          message = if _.isFunction(self.onbeforeunloadMessage) then self.onbeforeunloadMessage.call(null) else self.onbeforeunloadMessage
          if e
            e.returnValue = message
          return message

        i = 1
        while i <= streams
          parts.push
            from: partSize * (i-1)
            to:   partSize * i
            size: partSize
            part: i
            chunksQty: if @chunkSize < partSize then Math.ceil(partSize / @chunkSize) else 1
          i++

        end = (error, data) ->
          console.timeEnd('insert') if self.debug
          window.onbeforeunload = null
          result.progress.set 0
          onUploaded and onUploaded.call self, error, data

        if onBeforeUpload
          isUploadAllowed = onBeforeUpload.call file
          if isUploadAllowed isnt true
            end new Meteor.Error(403, if _.isString(isUploadAllowed) then isUploadAllowed else "onBeforeUpload() returned false"), null
            return false

        upload = (filePart, part, chunksQtyInPart, fileReader) ->
          currentChunk = 1
          first = true
          console.time("insertPart#{part}") if @debug

          fileReader.onload = (chunk) ->
            ++totalSentChunks
            progress = (uploaded / file.size) * 100
            result.progress.set progress
            onProgress and onProgress(progress)

            uploaded   += self.chunkSize
            arrayBuffer = chunk.srcElement or chunk.target
            unitArray   = new Uint8Array arrayBuffer.result
            last        = (part is streams and currentChunk >= chunksQtyInPart)

            if chunksQtyInPart is 1
              Meteor.call self.methodNames.MeteorFileWrite, unitArray, fileData, meta, first, chunksQtyInPart, currentChunk, totalSentChunks, randFileName, part, streams, file.size, (error, data) ->
                if data.last
                  end error, data
            else
              Meteor.call self.methodNames.MeteorFileWrite, unitArray, fileData, meta, first, chunksQtyInPart, currentChunk, totalSentChunks, randFileName, part, streams, file.size, (error, data)->
                if not result.onPause.get()
                  if data.chunk + 1 <= chunksQtyInPart
                    from = currentChunk * self.chunkSize
                    to   = from + self.chunkSize

                    fileReader.readAsArrayBuffer filePart.slice from, to
                    currentChunk = ++data.chunk
                  else if data.last
                    end error, data
                else
                  result.continueFrom.push () ->
                    if data.chunk + 1 <= chunksQtyInPart
                      from = currentChunk * self.chunkSize
                      to   = from + self.chunkSize

                      fileReader.readAsArrayBuffer filePart.slice from, to
                      currentChunk = ++data.chunk
                    else if data.last
                      end error, data
            first = false

          fileReader.readAsArrayBuffer filePart.slice 0, self.chunkSize

        for part, i in parts
          part = parts[i]
          fileReader = new FileReader
          upload.call null, file.slice(part.from, part.to), i + 1, part.chunksQty, fileReader
          --i

        return result
  else
    undefined

  ###
  @isomorphic
  @function
  @class Meteor.Files
  @name remove
  @param {String|Object} search - `_id` of the file or `Object` like, {prop:'val'}
  @description Remove file(s) on cursor or find and remove file(s) if search is set
  @returns {undefined}
  ###
  remove: (search) ->
    console.info "Meteor.Files Debugger: [remove(#{search})]" if @debug
    check search, Match.Optional Match.OneOf Object, String

    if @checkAccess()
      @srch search
      if Meteor.isClient 
        Meteor.call @methodNames.MeteorFileUnlink, rcp(@)
        undefined

      if Meteor.isServer 
        files = @collection.find @search
        if files.count() > 0
          files.forEach (file) ->
            if file.versions and not _.isEmpty file.versions
              _.each file.versions, (version) ->
                fs.remove version.path
            else
              fs.remove file.path
        @collection.remove @search
        undefined

  ###
  @server
  @function
  @class Meteor.Files
  @name download
  @param {Object|Files} self - Instance of MEteor.Files
  @description Initiates the HTTP response
  @returns {undefined}
  ###
  download: if Meteor.isServer then (http, version = 'original') ->
    console.info "Meteor.Files Debugger: [download(#{http}, #{version})]" if @debug

    if not @public
      if @currentFile
        if _.has(@currentFile, 'versions') and _.has @currentFile.versions, version
          fileRef = @currentFile.versions[version]
        else
          fileRef = @currentFile
      else
        fileRef = false
    else
      search = {}
      search["versions.#{version}.path"] = "#{@storagePath}/#{http.params.file}"
      @currentFile = @collection.findOne(search)
      if @currentFile
        fileRef = @currentFile.versions[version]

    unless _.isObject(fileRef) and fs.existsSync fileRef.path
      console.warn "Meteor.Files Debugger: [download(#{http}, #{version})] [404] File not found: #{fileRef.path}" if @debug
      text = "File Not Found :("
      http.response.writeHead 404,
        'Content-Length': text.length
        'Content-Type':   "text/plain"
      http.response.end text
      return undefined

    else if @currentFile
      self       = @
      attachment = ''
      partiral   = false
      reqRange   = false
      fileStats  = fs.statSync fileRef.path

      if fileStats.size isnt fileRef.size and not @integrityCheck
        fileRef.size = fileStats.size
      else if fileStats.size isnt fileRef.size and @integrityCheck
        console.warn "Meteor.Files Debugger: [download(#{http}, #{version})] [400] Content-Length mismatch!: #{fileRef.path}" if @debug
        text = "Content-Length mismatch!"
        http.response.writeHead 400,
          'Cache-Control': 'no-cache'
          'Content-Length': text.length
          'Content-Type':   "text/plain"
        http.response.end text
        return undefined

      if http.params.query.download and http.params.query.download == 'true'
        attachment = 'attachment; '

      if http.request.headers.range
        partiral = true
        array    = http.request.headers.range.split /bytes=([0-9]*)-([0-9]*)/
        start    = parseInt array[1]
        end      = parseInt array[2]
      else
        start    = 0
        end      = fileRef.size

      if partiral or (http.params.query.play and http.params.query.play == 'true')
        reqRange =
          Start: if isNaN(start) then 0 else start
          End: if isNaN(end) then (fileRef.size) else end
        if not isNaN(start) and isNaN(end)
          reqRange.Start = start
          reqRange.End   = fileRef.size
        if isNaN(start) and not isNaN(end) 
          reqRange.Start = fileRef.size - end
          reqRange.End   = fileRef.size

        if (@strict and not http.request.headers.range) or reqRange.Start > fileRef.size or reqRange.End > fileRef.size
          console.info "Meteor.Files Debugger: [download(#{http}, #{version})] [416] Content-Range is not specified!: #{fileRef.path}" if @debug
          http.response.writeHead 416,
            'Content-Range':        "bytes */#{fileRef.size}"
            'Pragma':               'public'
            'Expires':              -1
            'Cache-Control':        'public, must-revalidate, post-check=0, pre-check=0'
            'Content-Type':         fileRef.type
            'Accept-Ranges':        'bytes'
          http.response.end()
          return undefined
        else
          console.info "Meteor.Files Debugger: [download(#{http}, #{version})] [206]: #{fileRef.path}" if @debug
          _cacheControl = if (http.params.query.play and http.params.query.play == 'true') then 'public, must-revalidate, post-check=0, pre-check=0' else @cacheControl
          stream = fs.createReadStream fileRef.path, {start: reqRange.Start, end: reqRange.End}
          stream.on 'open', ->
            http.response.writeHead 206, 
              'Content-Range':        "bytes #{reqRange.Start}-#{reqRange.End}/#{fileRef.size}"
              'Pragma':               'public'
              'Expires':              -1
              'Cache-Control':        _cacheControl
              'Content-Type':         fileRef.type
              'Content-Disposition':  "#{attachment or 'inline; '}filename=\"#{encodeURI(self.currentFile.name)}\"; charset=utf-8"
              'Content-Length':       if reqRange.Start == reqRange.End then 0 else (reqRange.End - reqRange.Start);
              'Accept-Ranges':        'bytes'
            stream.pipe http.response
          return undefined

      else
        console.info "Meteor.Files Debugger: [download(#{http}, #{version})] [200]: #{fileRef.path}" if @debug
        stream = fs.createReadStream fileRef.path
        stream.on 'open', ->
          http.response.writeHead 200, 
            'Content-Range':        "bytes 0-#{fileRef.size}/#{fileRef.size}"
            'Cache-Control':        self.cacheControl
            'Content-Type':         fileRef.type
            'Content-Disposition':  "#{attachment or 'inline; '}filename=\"#{encodeURI(self.currentFile.name)}\"; charset=utf-8"
            'Content-Length':       fileRef.size
            'Accept-Ranges':        'bytes'
          stream.pipe http.response
        return undefined
  else
    undefined

  ###
  @isomorphic
  @function
  @class Meteor.Files
  @name link
  @param {Object} fileRef - File reference object
  @param {String} version - [Optional] Version of file you would like to request
  @description Returns link
  @returns {String}
  ###
  link: (fileRef, version = 'original', pub = false) ->
    console.info "Meteor.Files Debugger: [link()]" if @debug
    if _.isString fileRef
      version = fileRef 
      fileRef = undefined
    return undefined if not fileRef and not @currentFile

    if @public
      return formatFleURL fileRef or @currentFile, version, true
    else
      return formatFleURL fileRef or @currentFile, version, false

formatFleURL = (fileRef, version = 'original', pub = false) ->
  if pub
    return "#{fileRef._downloadRoute}/#{version}-#{fileRef._id}.#{fileRef.extension}" 
  else
    return "#{fileRef._downloadRoute}/#{fileRef._collectionName}/#{fileRef._id}/#{version}/#{fileRef._id}.#{fileRef.extension}"

if Meteor.isClient
  ###
  @client
  @TemplateHelper
  @name fileURL
  @param {Object} fileRef - File reference object
  @param {String} version - [Optional] Version of file you would like to request
  @description Get download URL for file by fileRef, even without subscription
  @example {{fileURL fileRef}}
  @returns {String}
  ###
  Template.registerHelper 'fileURL', (fileRef, version) ->
    return undefined if not fileRef or not _.isObject fileRef
    version = if not _.isString version then 'original' else version
    if fileRef._id
      if fileRef._storagePath.indexOf('../web.browser') isnt -1
        return formatFleURL fileRef, version, true
      else
        return formatFleURL fileRef, version, false
    else
      null