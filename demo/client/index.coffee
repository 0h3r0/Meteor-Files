Template.index.onCreated ->
  @take           = new ReactiveVar 50
  @filesLength    = new ReactiveVar 0
  @getFilesLenght = =>
    Meteor.call 'filesLenght', (error, length) =>
      if error
        console.error error
      else
        @filesLength.set length
  @getFilesLenght()

  @autorun => _app.subs.subscribe 'latest', @take.get()

Template.index.helpers
  take:        -> Template.instance().take.get()
  removedIn:   -> moment(@meta.expireAt).fromNow()
  filesLength: -> Template.instance().filesLength.get()

Template.index.events
  'click #loadMore': (e, template) -> template.take.set template.take.get() + 50