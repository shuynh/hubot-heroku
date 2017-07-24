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
#   hubot heroku restart <app-name> - restarts the specified app

Heroku          = require('heroku-client')
objectToMessage = require("../object-to-message")

heroku = new Heroku(token: process.env.HEROKU_API_KEY)
_      = require('lodash')
moment = require('moment')

module.exports = (robot) ->

  respondToUser = (robotMessage, error, successMessage) ->
    if error
      robotMessage.reply "Shucks. An error occurred. #{error.statusCode} - #{error.body.message}"
    else
      robotMessage.reply successMessage

  # Migration
  robot.respond /heroku migrate (.*)/i, (msg) ->
    
    appName = msg.match[1]

    heroku.apps(appName).dynos().create
      command: "rake db:migrate"
      attach: false
    , (error, dyno) ->
      respondToUser(msg, error, "Running migrations for #{appName}")

      heroku.apps(appName).logSessions().create
        dyno: dyno.name
        tail: true
      , (error, session) ->
        respondToUser(msg, error, "View logs at: #{session.logplex_url}")

  # Rollback
  robot.respond /heroku rollback (.*) to (.*)$/i, (msg) ->
    
    appName = msg.match[1]
    version = msg.match[2]

    if version.match(/v\d+$/)
      msg.reply "Rolling back #{appName} to #{version}"

      app = heroku.apps(appName)
      app.releases().list (error, releases) ->
        release = _.find releases, (release) ->
          "v#{release.version}" ==  version

        return msg.reply "Version #{version} not found for #{appName} :(" unless release

        app.releases().rollback release: release.id, (error, release) ->
          respondToUser(msg, error, "Success! v#{release.version} -> Rollback to #{version}")
  
  # Restart
  robot.respond /heroku restart ([\w-]+)\s?(\w+(?:\.\d+)?)?/i, (msg) ->
    
    appName = msg.match[1]
    dynoName = msg.match[2]
    dynoNameText = if dynoName then ' '+dynoName else ''

    unless dynoName
      heroku.apps(appName).dynos().restartAll (error, app) ->
        respondToUser(msg, error, "Heroku: Restarting #{appName}")
    else
      heroku.apps(appName).dynos(dynoName).restart (error, app) ->
        respondToUser(msg, error, "Heroku: Restarting #{appName}#{dynoNameText}")

  # Releases
  robot.respond /heroku releases (.*)$/i, (msg) ->
    appName = msg.match[1]

    heroku.apps(appName).releases().list (error, releases) ->
      output = []
      if releases
        output.push "Recent releases of #{appName}"

        for release in releases.sort((a, b) -> b.version - a.version)[0..9]
          output.push "v#{release.version} - #{release.description} - #{release.user.email} -  #{release.created_at}"

      respondToUser(msg, error, output.join("\n"))
