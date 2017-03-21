import fs             from 'fs'
import path           from 'path'
import builtins       from 'builtin-modules'
import browserResolve from 'browser-resolve'
import nodeResolve    from 'resolve'
import chalk          from 'chalk'

COMMONJS_BROWSER_EMPTY = nodeResolve.sync 'browser-resolve/empty.js', __dirname
ES6_BROWSER_EMPTY      = path.resolve __dirname, '../src/empty.js'


export default (opts = {}) ->
  basedir        = opts.basedir        ? null
  browser        = opts.browser        ? false
  extensions     = opts.extensions     ? ['.js', '.json', '.coffee', '.pug', '.styl']
  preferBuiltins = opts.preferBuiltins ? true
  skip           = opts.skip           ? []
  external       = opts.external       ? true

  if Array.isArray opts.external
    external = false
    skip     = skip.concat opts.external

  skip = new Set skip

  resolveId = if browser then browserResolve else nodeResolve

  name: 'node-resolve-magic'
  resolveId: (importee, importer) ->
    return null if /\0/.test importee # Ignore IDs with null character, these belong to other plugins
    return null if !importer          # Disregard entry module

    parts = importee.split /[\/\\]/
    id    = parts.shift()

    basedir = opts.basedir ? path.dirname importer

    if id[0] == '@' && parts.length
      # scoped packages
      id += "/#{parts.shift()}"
    else if id[0] == '.'
      # An import relative to the parent dir of the importer, force basedir to
      # match importer
      basedir  = path.dirname importer
      id       = path.resolve importer, '..', importee
      relative = true

    return if skip.has id

    new Promise (resolve, reject) ->
      _opts =
        basedir:    basedir
        extensions: extensions
        packageFilter: (pkg) ->
          # Try in order: 'module', 'jsnext:main' and 'main' fields.
          if pkg.module
            pkg.main = pkg.module
          else if pkg['jsnext:main']
            pkg.main = pkg['jsnext:main']
          unless pkg.main
            pkg.main = './index.js'

          # Automatically detect new externals based on package.json if opts.
          # Typically a bundled library will only include dependencies which
          # have not been processed into the build for some reason. We'll
          # likewise defer processing these (unless forced)
          if external == true and pkg.module?
            for k of pkg.dependencies
              continue if skip.has k
              console.log " - #{k}" + chalk.black " detected as external to #{pkg.name}"
              skip.add k

          pkg

      resolveId importee, _opts, (err, resolved) ->
        return reject Error "Could not resolve '#{importee}' from #{path.normalize importer}" if err?

        # Empty modules?
        if resolved == COMMONJS_BROWSER_EMPTY
          return resolve ES6_BROWSER_EMPTY

        # Built-in module previously resolved?
        if ~builtins.indexOf resolved
          return resolve null

        # Prefer built-ins
        if preferBuiltins and ~builtins.indexOf importee
          unless opts.quiet
            console.log " - #{importee}" + chalk.black " built-in preferred over local alternative"
            skip.add importee
          return resolve null

        # Resolve symlinks
        fs.exists resolved, (exists) ->
          unless exists
            unless opts.quiet
              console.log "resolved #{importee} to #{resolved}, which does not exist"
            return resolve null

          fs.realpath resolved, (err, resolved) ->
            return reject err if err?

            resolve resolved
