FlowRouter.route '/',
  name: 'index'
  action: (params, queryParams, data) ->
    @render '_layout', 'index', data
    return
  waitOn: (params) -> [_app.subs.subscribe('latest', 10)]
  whileWaiting: ->
    @render '_layout', '_loading'
    return
  data: ->
    latest: Collections.files.collection.find {userId: $ne: Meteor.userId()}, sort: 'meta.created_at': -1
    userFiles: Collections.files.collection.find {userId: Meteor.userId()}, sort: 'meta.created_at': -1

FlowRouter.route '/login',
  name: 'login'
  title: -> 'Login into Meteor Files'
  action: ->
    @render '_layout', 'login'
    return

FlowRouter.route '/:_id',
  name: 'file'
  title: (params, queryParams, file) ->
    if file 
      file = file.fetch()?[0]
      return if file.name then "View File: #{file.name}" else '404: Page not found'
    else
      return '404: Page not found'
  action: (params, queryParams, file) ->
    @render '_layout', 'file', {file}
    return
  waitOn: (params) -> [_app.subs.subscribe('file', params._id)]
  whileWaiting: ->
    @render '_layout', '_loading'
    return
  onNoData: ->
    @render '_layout', '_404'
    return
  data: (params) -> 
    if Collections.files.collection.findOne params._id
      return Collections.files.collection.find params._id
    else
      return false