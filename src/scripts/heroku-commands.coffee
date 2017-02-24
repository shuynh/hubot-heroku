# Description:
#   Exposes Heroku commands to hubot
#
# Dependencies:
#   "heroku-client": "^1.9.0"
#   "hubot-auth": "^1.2.0"
#
# Configuration:
#   HUBOT_HEROKU_API_KEY
#
# Commands:
#   hubot heroku migrate <app-name> - runs migrations 
#   hubot heroku rollback <app-name> to <version> - rolls back release 

Heroku          = require('heroku-client')
objectToMessage = require("../object-to-message")

heroku = new Heroku(token: process.env.HEROKU_API_KEY)
_      = require('lodash')
moment = require('moment')
useAuth = (process.env.HUBOT_HEROKU_USE_AUTH or '').trim().toLowerCase() is 'true'

module.exports = (robot) ->

  respondToUser = (robotMessage, error, successMessage) ->
    if error
      robotMessage.reply "Shucks. An error occurred. #{error.statusCode} - #{error.body.message}"
    else
      robotMessage.reply successMessage

  # Migration
  robot.respond /heroku migrate\s+(bedpost\-staging|bedpost\-production)$/i, (msg) ->
    unless robot.auth.hasRole(msg.envelope.user,'admin')
      msg.send 'Sorry! You do not have deploy permissions. Please contact ops.'
      return
    
    appName = msg.match[1]

    msg.reply "Running migrations on #{appName}"

    heroku.apps(appName).dynos().create
      command: "rake db:migrate"
      attach: false
    , (error, dyno) ->
      respondToUser(msg, error, "Heroku: Running migrations for #{appName}")

      heroku.apps(appName).logSessions().create
        dyno: dyno.name
        tail: true
      , (error, session) ->
        respondToUser(msg, error, "View logs at: #{session.logplex_url}")

  # Rollback
  robot.respond /heroku rollback (bedpost\-staging|bedpost\-production) to (\w+)$/i, (msg) ->
    appName = msg.match[1]
    version = msg.match[2]

    return unless auth(msg, appName)

    if version.match(/v\d+$/)
      msg.reply "Rolling back #{appName} to #{version}"

      app = heroku.apps(appName)
      app.releases().list (error, releases) ->
        release = _.find releases, (release) ->
          "v#{release.version}" ==  version

        return msg.reply "Version #{version} not found for #{appName} :(" unless release

        app.releases().rollback release: release.id, (error, release) ->
          respondToUser(msg, error, "Success! v#{release.version} -> Rollback to #{version}")

  # App List
  robot.respond /(heroku list apps)\s?(.*)/i, (msg) ->
    return unless auth(msg)

    searchName = msg.match[2] if msg.match[2].length > 0

    if searchName
      msg.reply "Listing apps matching: #{searchName}"
    else
      msg.reply "Listing all apps available..."

    heroku.apps().list (error, list) ->
      list = list.filter (item) -> item.name.match(new RegExp(searchName, "i"))

      result = if list.length > 0 then list.map((app) -> objectToMessage(app, "appShortInfo")).join("\n\n") else "No apps found"

      respondToUser(msg, error, result)

  # Releases
  robot.respond /heroku releases (.*)$/i, (msg) ->
    appName = msg.match[1]

    return unless auth(msg, appName)

    msg.reply "Getting releases for #{appName}"

    heroku.apps(appName).releases().list (error, releases) ->
      output = []
      if releases
        output.push "Recent releases of #{appName}"

        for release in releases.sort((a, b) -> b.version - a.version)[0..9]
          output.push "v#{release.version} - #{release.description} - #{release.user.email} -  #{release.created_at}"

      respondToUser(msg, error, output.join("\n"))
