// Description:
//   Exposes Heroku commands to hubot
//
// Dependencies:
//   "heroku-client": "^1.9.0"
//   "hubot-auth": "^1.2.0"
//
// Configuration:
//   HUBOT_HEROKU_API_KEY
//
// Commands:
//   hubot heroku releases <app> - Latest 10 releases
//   hubot heroku rollback <app> to <version> - Rollback to a release
//   hubot heroku restart <app> - Restarts the specified app 
//   hubot heroku migrate <app> - Runs migrations. Remember to restart the app =)
//
// Author:
//   daemonsy

const Heroku = require('heroku-client');
const objectToMessage = require("../object-to-message");
const responder = require("../responder");
const commandsWhitelist = require("../values/commands-whitelist");

let heroku = new Heroku({ token: process.env.HUBOT_HEROKU_API_KEY });
const _ = require('lodash');
const moment = require('moment');
let useAuth = (process.env.HUBOT_HEROKU_USE_AUTH || '').trim().toLowerCase() === 'true';

module.exports = function(robot) {
  let auth = function(msg, appName) {
    let hasRole, role;
    if (appName) {
      role = `heroku-${appName}`;
      hasRole = robot.auth.hasRole(msg.envelope.user, role);
    }

    let isAdmin = robot.auth.hasRole(msg.envelope.user, 'deployer');

    if (useAuth && !(hasRole || isAdmin)) {
      responder(msg).say(`Access denied. You must have this role to use this command: ${role}`);
      return false;
    }
    return true;
  };

  let respondToUser = function(robotMessage, error, successMessage) {
    if (error) {
      console.log("There is error!", error);
      return robotMessage.reply(`Shucks. An error occurred. ${error.statusCode} - ${error.body.message}`);
    } else {
      return robotMessage.reply(successMessage);
    }
  };

  // Rollback
  robot.respond(/heroku rollback (.*) to (.*)$/i, function(msg) {
    let appName = msg.match[1];
    let version = msg.match[2];

    if (!auth(msg, appName)) { return; }

    if (version.match(/v\d+$/)) {
      responder(msg).say(`Rolling back to ${version}`);

      heroku.get(`/apps/${appName}/releases`).then(releases => {
        let release = _.find(releases, release => `v${release.version}` ===  version);

        if (!release) { throw `Version ${version} not found for ${appName} :(`; }

        return heroku.post(`/apps/${appName}/releases`, { body: { release: release.id } });
      }).then(release => responder(msg).say(`Success! v${release.version} -> Rollback to ${version}`))
        .catch(error => responder(msg).say(error));
    }
  });

  // Restart
  robot.respond(/heroku restart ([\w-]+)\s?(\w+(?:\.\d+)?)?/i, function(msg) {
    let appName = msg.match[1];
    let dynoName = msg.match[2];
    let dynoNameText = dynoName ? ` ${dynoName}` : '';

    if (!auth(msg, appName)) { return; }

    responder(msg).say(`Telling Heroku to restart ${appName}${dynoNameText}`);

    if (!dynoName) {
      heroku.delete(`/apps/${appName}/dynos`).then(app => responder(msg).say(`Heroku: Restarting ${appName}${dynoNameText}`));
    } else {
      heroku.delete(`/apps/${appName}/dynos/${dynoName}`).then(app => responder(msg).say(`Heroku: Restarting ${appName}${dynoNameText}`));
    }
  });

  // Migration
  robot.respond(/heroku migrate (.*)/i, function(msg) {
    let appName = msg.match[1];

    if (!auth(msg, appName)) { return; }

    heroku.post(`/apps/${appName}/dynos`, {
      body: {
        command: "rake db:migrate",
        attach: false
      }
    }).then(dyno => {
      responder(msg).say(`Heroku: Running migrations for ${appName}`);

      return heroku.post(`/apps/${appName}/log-sessions`, {
        body: {
          dyno: dyno.name,
          tail: true
        }
      })
    }).then(session => responder(msg).say(`View logs at: ${session.logplex_url}`));
  });

  // Run <command> <task> <app>
  robot.respond(/heroku run (\w+) (.+) (?:--app .+|(.+)$)/i, function(msg) {
    let command = msg.match[1].toLowerCase();
    let task = msg.match[2].replace("--app", "").trim();
    let appName = msg.match[3];

    if (!commandsWhitelist.includes(command)) { return responder(msg).say("only rake and thor is supported"); }
    if (!auth(msg, appName)) { return; }

    responder(msg).say(`Telling Heroku to run \`${command} ${task}\` on ${appName}`);

    heroku.post(`/apps/${appName}/dynos`, {
      body: {
        command: `${command} ${task}`,
        attach: false
      }
    }).then(dyno => {
      responder(msg).say(`Heroku: Running \`${command} ${task}\` for ${appName}`);

      return heroku.post(`/apps/${appName}/log-sessions`, {
        body: {
          dyno: dyno.name,
          tail: true
        }
      })
    }).then(session => responder(msg).say(`View logs at: ${session.logplex_url}`));
  });
};
