# 职责是
# 1. 插入script节点
# 2. 读取参数ignored,
# 3. 读取/reload---uid.js 等信息 ,并及时反馈

path = require 'path'

# local module
chokidar = require 'chokidar'
express = require 'express'
helper = require "./helper"

cwd = do process.cwd


# connect middleware
# =====================================
# middleware options:
#
#   * dir: watcher dir (defaults process.cwd())
#   * fileType: watched fileType(defaults 'js|css|html|xhtml')

module.exports = (app, server, options) ->
  app.use '/puer', express.static path.join __dirname, "../vendor" 

  options.fileType ?= 'js|css|html|xhtml'
  options.inject ?= []

  if(!options.dir) 
    throw Error("dir option is need to watch")
  if(options.reload)
    options.inject.push '<script src="/puer/js/reload.js"></script>'
    watcher = chokidar.watch options.dir, 
      ignored: new RegExp('\\.(?!(' + options.fileType + ')$)')
      persistent: true

    helper.log "watcher on!!"

    io = (require 'socket.io').listen server
    io.set("log level", 1)

    # keep the connect socket instance
    sockets = []
    # bind one listener to avoid memory leak

    watcher.on 'change', (path, stats) ->
      data = "path": path
      # if css file modified   dont't reload page just update the link.href
      data.css = path.slice cwd.length if ~path.indexOf ".css"

      for socket in sockets
        socket.emit "update", data if socket

      # helper.log "fileChange #{path}"
    io.sockets.on "connection" , (socket) ->
      sockets.push socket
      socket.on 'disconnect', ->
        index = sockets.indexOf socket
        if index != -1
          sockets.splice index, 1
  

  (req, res, next) ->
    # proxy
    write = res.write
    end = res.end
    # use res.noinject to forbit relad or weinre inject
    if res.noinject != true
      res.write = (chunk, encoding) ->
        header = res.getHeader "content-type"
        length = res.getHeader "content-length"
        if (/^text\/html/.test header) or not header
          if Buffer.isBuffer(chunk)
            chunk = chunk.toString("utf8")
          return write.call res, chunk, "utf8" if not ~chunk.indexOf("</head>") 
          chunk = chunk.replace "</head>", options.inject.join('') + "</head>"
          # need set length 
          if length
            length = parseInt(length)
            length += Buffer.byteLength options.inject.join('')
            res.setHeader "content-length", length

          write.call res, chunk, "utf8"
        else 
          write.call res, chunk, encoding

      res.end = (chunk, encoding) ->
        this.write chunk, encoding if chunk?
        end.call(res)

    do next


