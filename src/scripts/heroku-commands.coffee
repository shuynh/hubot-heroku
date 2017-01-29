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
#   hubot heroku releases <app> - Latest 10 releases
#   hubot heroku restart <app> <dyno> - Restarts the specified app or dyno/s (e.g. worker or web.2)
#   hubot heroku config <app> - Get config keys for the app. Values not given for security
#   hubot heroku config:set <app> <KEY=value> - Set KEY to value. Case sensitive and overrides present key
#   hubot heroku config:unset <app> <KEY> - Unsets KEY, does not throw error if key is not present
#
# Author:
#   daemonsy

Heroku          = require('heroku-client')
objectToMessage = require("../object-to-message")

heroku = new Heroku(token: process.env.HEROKU_API_KEY)
_      = require('lodash')
moment = require('moment')
useAuth = (process.env.HUBOT_HEROKU_USE_AUTH or '').trim().toLowerCase() is 'true'

module.exports = (robot) ->
  auth = (msg, appName) ->
    if appName
      role = "heroku-#{appName}"
      hasRole = robot.auth.hasRole(msg.envelope.user, role)

    isAdmin = robot.auth.hasRole(msg.envelope.user, 'admin')

    if useAuth and not (hasRole or isAdmin)
      msg.reply "Access denied. You must have this role to use this command: #{role}"
      return false
    return true

  respondToUser = (robotMessage, error, successMessage) ->
    if error
      robotMessage.reply "Shucks. An error occurred. #{error.statusCode} - #{error.body.message}"
    else
      robotMessage.reply successMessage

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

  # Restart
  robot.respond /heroku restart ([\w-]+)\s?(\w+(?:\.\d+)?)?/i, (msg) ->
    appName = msg.match[1]
    dynoName = msg.match[2]
    dynoNameText = if dynoName then ' '+dynoName else ''

    return unless auth(msg, appName)

    msg.reply "Telling Heroku to restart #{appName}#{dynoNameText}"

    unless dynoName
      heroku.apps(appName).dynos().restartAll (error, app) ->
        respondToUser(msg, error, "Heroku: Restarting #{appName}")
    else
      heroku.apps(appName).dynos(dynoName).restart (error, app) ->
        respondToUser(msg, error, "Heroku: Restarting #{appName}#{dynoNameText}")

  # Config Vars
  robot.respond /heroku config (.*)$/i, (msg) ->
    appName = msg.match[1]

    return unless auth(msg, appName)

    msg.reply "Getting config keys for #{appName}"

    heroku.apps(appName).configVars().info (error, configVars) ->
      listOfKeys = configVars && Object.keys(configVars).join(", ")
      respondToUser(msg, error, listOfKeys)

  robot.respond /heroku config:set (.*) (\w+)=('([\s\S]+)'|"([\s\S]+)"|([\s\S]+\b))/im, (msg) ->
    keyPair = {}

    appName = msg.match[1]
    key     = msg.match[2]
    value   = msg.match[4] || msg.match[5] || msg.match[6] # :sad_panda:

    return unless auth(msg, appName)

    msg.reply "Setting config #{key} => #{value}"

    keyPair[key] = value

    heroku.apps(appName).configVars().update keyPair, (error, configVars) ->
      respondToUser(msg, error, "Heroku: #{key} is set to #{configVars[key]}")

  robot.respond /heroku config:unset (.*) (\w+)$/i, (msg) ->
    keyPair = {}
    appName = msg.match[1]
    key     = msg.match[2]
    value   = msg.match[3]

    return unless auth(msg, appName)

    msg.reply "Unsetting config #{key}"

    keyPair[key] = null

    heroku.apps(appName).configVars().update keyPair, (error, response) ->
      respondToUser(msg, error, "Heroku: #{key} has been unset")

