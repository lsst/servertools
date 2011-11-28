#! /usr/bin/env python
#
from __future__ import with_statement
import sys, os, re, optparse, shutil

from lsstdistrib.release import UpdateDependents
from lsstdistrib import version as onvers

prog = os.path.basename(sys.argv[0])
if prog.endswith(".py"):
    prog = prog[:-3]

usage = "%prog [ -h ] [ -vs ] -d DIR product ..."
description = \
"""Create new manifest files for all dependents of the given products, up-reving them
to use this products.  Normally, the products that are specified have been recently
released.  
"""

log = sys.stderr

defaultServerRoot=None

def main():
    global log
    cl = setopts()
    (opts, args) = cl.parse_args()

    if not opts.serverdir:
        fail("-d option missing from arguments", 2)
    if not os.path.isdir(opts.serverdir):
        fail("server root given with -d is not an existing directory:\n" + 
             opts.serverdir, 2)
    if len(args) < 1:
        fail("no products specified", 2)

    if opts.silent:
        log = None

    products = []
    for arg in args:
        products.append(parseProduct(arg))

    if opts.uprprods:
        tmp = []
        for i in opts.uprprods:
            tmp.extend(i.split(','))
        opts.uprprods = tmp

    uprev = UpdateDependents(products, opts.serverdir, log=log)
    if opts.reftag:
        uprev.updateFromTag(opts.reftag)
        
    if opts.uprprods:
        # restrict the products we up-rev
        deps = uprev.getDependents()
        for prodname in deps.keys():
            if prodname not in opts.uprprods:
                del deps[prodname]
        uprev.setDependents(deps)
        
    if opts.noaction:
        if not opts.silent:
            print >> log, "No new files being written;", \
                "here's what we would write without --noaction:"
        updated = getNewManifestPaths(uprev)
    else:
        updated = uprev.createManifests()

    ostrm = sys.stdout
    if opts.outfile:
        ostrm = open(opts.outfile, 'w')

    if opts.outfile or opts.release or not opts.silent:
        for prod in updated:
            if opts.release:
                writtenfile = "%s-%s+%s.manifest" % (prod[0],prod[1],prod[2])
                prodpath = os.path.join(opts.serverdir,'manifests',writtenfile)
                            
                if not opts.noaction:
                    # print "cp", prod[3], deployedpath
                    shutil.copyfile(prod[3], prodpath)
            else:
                writtenfile = prod[3]
                if writtenfile.startswith(opts.serverdir + '/'):
                    writtenfile = writtenfile[len(opts.serverdir)+1:]

            print >> ostrm, writtenfile
            if opts.outfile and opts.verbose:
                print writtenfile

    if opts.outfile:
        ostrm.close()

def parseProduct(prodpath):
    fields = prodpath.split('/')
    if len(fields) < 2:
        raise RuntimeError("bad product name syntax: " + prodpath)
    out = fields[-2:]
    isext = len(fields) > 2 and fields[-3] == 'external'
    out.append(isext)
        
    return out

def getNewManifestPaths(uprev):
    deps = uprev.getDependents()
    blds = uprev.setUpgradedBuildNumbers()

    out = []
    for prod in deps:
        pdir = uprev.server.getProductDir(prod, deps[prod])
        filename = "b%s.manifest" % blds[prod]
        out.append( (prod, onvers.baseVersion(deps[prod]), 
                         blds[prod], os.path.join(pdir, filename)) )

    return out

def setopts():
    parser = optparse.OptionParser(prog=prog, usage=usage, 
                                   description=description)
    parser.add_option("-v", "--verbose", action="count", dest="verbose",
                      default=0, help="print extra messages")
    parser.add_option("-s", "--silent", action="store_true", dest="silent",
                      default=False, help="suppress all output")
    parser.add_option("-d", "--server-dir", action="store", dest="serverdir",
                      metavar="DIR", default=defaultServerRoot,
                      help="the root directory of the distribution server")
    parser.add_option("-o", "--output-file", action="store", dest="outfile",
                      metavar="FILE", 
                      help="a file to write the list of updated manifest files")
    parser.add_option("-u", "--update-products", action="append", 
                      metavar="NAME[,NAME...]", dest="uprprods",
                      help="a comma-separated list of product names to restrict the up-revs to")
    parser.add_option("-T", "--reference-tag", action="store", dest="reftag",
                      metavar="TAG", default="current",
          help="use the given tag as a guide for choosing dependency versions")
    parser.add_option("-r", "--release", action="store_true", default=False,
                      dest="release",
                      help="actually deploy manifests into manifest directory, making the new builds available to clients")
    parser.add_option("-n", "--noaction", action="store_true", default=False,
                      dest="noaction", 
                      help="do not actually write any files; just print the names that would be written")

    return parser

def fail(msg, exitcode=1):
    raise FatalError(msg, exitcode)

class FatalError(Exception):
    def __init__(self, msg, exitcode):
        Exception.__init__(self, msg)
        self.exitcode = exitcode


if __name__ == "__main__":
    try:
        main()
    except FatalError, ex:
        if log:
            print >> log, "%s: %s" % (prog, str(ex))
        sys.exit(ex.exitcode)


        
