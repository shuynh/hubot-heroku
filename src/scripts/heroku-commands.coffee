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
#   hubot heroku list apps <app name filter> - Lists all apps or filtered by the name
#   hubot heroku dynos <app> - Lists all dynos and their status
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

