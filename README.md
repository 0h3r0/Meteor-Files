Meteor-Files
========
This package allows to:
 - Upload file(s) via DDP
    * Small files
    * Huge files, tested on 100GB (Note Browser will eat 7%-10% RAM of the file size)
    * Pause / Resume upload
 - Write file in file system
    * Automatically writes uploaded files on FS and special Collection
    * You able to specify `path`, collection name, schema, chunk size and naming function
 - File streaming from server via HTTP
    * Correct `mime-type` and `Content-Range` headers
    * Correct `206` and `416` responses
 - Download uploaded files from server via HTTP
    * You able to specify `route`
    * Download huge files via stream `pipe`, tested on 100GB
    * Fast download for small files
 - Store wherever you like
    * You may use `Meteor-Files` as temporary storage
    * After file is uploaded and stored on FS you able to `mv` or `cp` it's content 
 - Support of non-latin (non-Roman) file names
 - Subscribe on files you need


Why `Meteor-Files`?
========
`cfs` is a good package, but buggy cause it's huge monster which combine everything. In `Meteor-Files` is nothing to broke, it's simply upload/store/retrieve files to/from server. 
 - You need store to GridFS? - Add it yourself
 - You need to check file mime-type or extensions? - Add it yourself
 - You need to resize images after upload? - Add it yourself

Easy-peasy kids, yeah?

Install:
========
```shell
meteor add ostrio:files
```

API
========
##### `new Meteor.Files([storagePath], [collectionName], [downloadRoute], [schema], [chunkSize], [namingFunction], [debug])` [*Isomorphic*]

 - `storagePath` __String__ - Storage path on file system
    * Default value: `/assets/app/uploads`
 - `collectionName` __String__ - Collection name
    * Default value: `MeteorUploadFiles`
 - `downloadRoute` __String__ - Server Route used to retrieve files
    * Default value: `/cdn/storage`
 - `schema` __Object__ - Collection Schema (*Not editable for current release*)
 - `chunkSize` __Number__ - Upload chunk size
    * Default value: `272144`
 - `namingFunction` __Function__ - Function which returns `String`
    * Default value: `String.rand`
 - `debug` __Boolean__ - Turn on/of debugging and extra logging
    * Default value: `false`

```coffeescript
myFiles.cacheControl = 'public, max-age=31536000' # Set 'Cache-Control' header for downloads

myFiles = new Meteor.Files '/assets/app/uploads/myFiles', 'myFiles', '/downloads/myFiles'

if Meteor.isClient
  myFiles.collection.subscribe "MeteorFileSubs", postId.get()

if Meteor.isServer
  Meteor.publish "MeteorFileSubs", (postId) ->
    myFiles.collection.find {'meta.postId': postId}

myFiles.insert(file) # Upload file

myFiles.find({'meta.userId': Meteor.userId()}).cursor   # Current collection cursor
myFiles.find({'meta.userId': Meteor.userId()}).get()    # Array of fetched rows
myFiles.find({'meta.userId': Meteor.userId()}).remove() # Remove all files on the cursor

myFiles.remove({'meta.userId': Meteor.userId()})        # Remove all files returned by passed search
myFiles.remove(fileRef._id)           # Remove file by ID

myFiles.findOne(fileRef._id).get()    # Get fileRef
myFiles.findOne(fileRef._id).link()   # Get download link
myFiles.findOne(fileRef._id).remove() # Remove file
```

##### File streaming:
To stream file add `?play=true` query to download link.
```coffeescript
audio = new Meteor.Files()

if Meteor.isClient
  Template.my.helpers
    audiofiles: ->
      audio.find({'meta.post': postId}).cursor
```

In template:
```jade
template(name="my")
  ul
    each audiofiles
      li 
        audio(preload="auto" controls="true")
          source(src="{{fileURL this}}?play=true" type="{{type}}")
```

##### File download:
To download file use `fileURL` template helper. Data will be transfered via pipe, - just add `?download=true` query to link, so server will send file directly. Use `?download=true` query for smaller files, for big files - just use plain link without query.
```coffeescript
uploads = new Meteor.Files()

if Meteor.isClient
  Template.my.helpers
    files: ->
      uploads.find({'meta.post': postId}).cursor
```

In template:
```jade
template(name="my")
  ul
    each files
      li 
        a(href="{{fileURL this}}?download=true") name
```


##### Current schema:
```coffeescript
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
isVideo:
  type: Boolean
isAudio:
  type: Boolean
isImage:
  type: Boolean
size:
  type: Number
```

Template Helper
==========
To get download URL for file, you only need `fileRef` object, so there is no need for subscription
```jade
a(href="{{fileURL fileRef}}?download=true" download) {{fileRef.name}}
```

Methods
==========
##### `insert(file, [meta], [onUploaded], [onProgress], [onBeforeUpload])` [*Client*]
Returns `FileReader` instance, so you can call `abort()` or any other method to control, `pause` or `resume` upload process, read more: [FileReader](https://developer.mozilla.org/en-US/docs/Web/API/FileReader).
 - `file` __File__ or __Object__ - HTML5 `files` item, like in change event: `e.currentTarget.files[0]`
 - `meta` __Object__ - Additional data as object, use later for search
 - `onUploaded` __Function__ - Callback triggered when upload is finished, with two arguments:
    * `error`
    * `fileRef` - see __Current schema__ section above
 - `onProgress` __Function__ - Callback triggered when chunk is sent, with only argument:
    * `progress` __Number__ - Current progress from `0` to `100`
 - `onBeforeUpload` __Function__ - Callback triggered right before upload is started, with only argument:
    * Context of the function is `File` - so you are able to check for extension, mime-type, size and etc.
    * `FileReader` __FileReader__ - Current progress from `0` to `100`
    * __return__ `true` to continue
    * __return__ `false` to abort upload

```coffeescript
# For example we upload file for blog post
post = Posts.findOne(someId) # Get blog post reference
uploads = new Meteor.Files() # Create Meteor.Files instance

if Meteor is client
  # Let's create progress-bar
  prgrs = new ReactiveVar false
  Template.my.helpers
    progress: ->
      prgrs.get()

  Template.my.events
    'change #file': (e) ->
      UIBlock.block i18n.get '_app.uploading' # See 'ostrio:uiblocker' and 'ostrio:i18n' packages

      _.each e.currentTarget.files, (file) ->
        uploads.insert file
        ,
          post: post._id # Add meta object with reference to blog post
        , 
          (error, fileRef) ->
            if not error
              doSomething fileRef.path, post._id, fileRef

            prgrs.set false
            $(e.target).val('')
            UIBlock.unblock()
        ,
          (progress) ->
            prgrs.set progress
        ,
          () ->
            # Set Allowed Extensions and max file size
            ['mp3', 'm4a'].inArray(@ext) and @size < 26214400 # See `ostrio:jsextensions` package
```

Progress bar in template (TWBS):
```jade
template(name="my")
  input.btn.btn-success#file(type="file")

  if progress
    .progress
      .progress-bar.progress-bar-striped.active(style="width:{{progress}}%")
        span.sr-only {{progress}}%
```

##### `findOne(search)`  [*Isomorphic*]
 - `search` __String__ or __Object__ - `_id` of the file or `Object`

```coffeescript
uploads = new Meteor.Files()

uploads.findOne('hdjJDSHW6784kJS').get()    # Get fileRef
uploads.findOne('hdjJDSHW6784kJS').remove() # Remove file
uploads.findOne('hdjJDSHW6784kJS').link()   # Get download link

uploads.findOne({'meta.post': post._id}).get()    # Get fileRef
uploads.findOne({'meta.post': post._id}).remove() # Remove file
uploads.findOne({'meta.post': post._id}).link()   # Get download link
```

##### `find(search)`  [*Isomorphic*]
 - `search` __String__ or __Object__ - `_id` of the file or `Object`

```coffeescript
uploads = new Meteor.Files()

uploads.find({'meta.post': post._id}).cursor   # Current cursor
uploads.find('hdjJDSHW6784kJS').get()          # Get array of fileRef(s)
uploads.find({'meta.post': post._id}).get()    # Get array of fileRef(s)
uploads.find({'meta.post': post._id}).remove() # Remove all files on cursor
```

##### `collection`  [*Isomorphic*]
Mongo Collection Instance - Use to fetch data. __Do not `remove` or `update`__ this collection

```coffeescript
uploads = new Meteor.Files()

if Meteor.isClient
  Meteor.subscribe "MeteorFileSubs", postId.get()

if Meteor.isServer
  Meteor.publish "MeteorFileSubs", (postId) ->
    uploads.collection.find {'meta.postId': postId}

uploads.collection.find({'meta.post': post._id})
uploads.collection.findOne('hdjJDSHW6784kJS')
```