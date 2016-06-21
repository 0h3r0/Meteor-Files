FlowRouter.globals.push
  title: 'Meteor Files: Upload and Share'

FlowRouter.globals.push
  meta:
    keywords: 
      name: 'keywords'
      itemprop: 'keywords'
      content: 'file, files, upload, store, storage, share, share files, meteor, open source, javascript'
    'og:url':
      property: 'og:url'
      content: -> _app.currentUrl()
    'og:title':
      property: 'og:title'
      content: -> document.title
    description:
      name: 'description'
      itemprop: 'description'
      property: 'og:description'
      content: 'Meteor Files: Upload, Serve and Manage files within Meteor application'
    'twitter:description': -> 'Meteor Files: Upload, Serve and Manage files within Meteor application'
    'twitter:title':       -> document.title
    'twitter:url':         -> _app.currentUrl()
    'og:image':
      property: 'og:image'
      content: Meteor.absoluteUrl 'icon_1200x630.png'
    'twitter:image':
      name: 'twitter:image'
      content: Meteor.absoluteUrl 'icon_750x560.png'

FlowRouter.notFound =
  action: -> 
    @render '_layout', '_404'
    return
  title: '404: Page not found'

new FlowRouterTitle FlowRouter
new FlowRouterMeta FlowRouter