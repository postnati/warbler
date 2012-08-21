/**
 * Copyright (c) 2010-2012 Engine Yard, Inc.
 * Copyright (c) 2007-2009 Sun Microsystems, Inc.
 * This source code is available under the MIT license.
 * See the file LICENSE.txt for details.
 */

import java.io.File;
import java.lang.reflect.Method;
import java.net.URI;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Enumeration;
import java.util.List;

public class JarMain implements Runnable {
  public static final String MAIN = "/" + JarMain.class.getName().replace('.', '/') + ".class";

  private String[] args;
  private String path, jarfile;
  private boolean debug;
  private File extractRoot;
  

  public JarMain(String[] args) throws Exception {
    this.args = args;
    URL mainClass = getClass().getResource(MAIN);
    this.path = mainClass.toURI().getSchemeSpecificPart();
    this.jarfile = this.path.replace("!" + MAIN, "").replace("file:", "");
    this.debug = isDebug();
    Runtime.getRuntime().addShutdownHook(new Thread(this));
  }

  private URL[] extractJRuby() throws Exception {
    List<URL> urls = new ArrayList<URL>();

    URI basePath = new URI("file://" + this.jarfile);

    File dir = (new File(this.jarfile)).getParentFile();
    String[] strs = dir.list();

    for (int i = 0; i < strs.length; i++) {
      if(strs[i].matches("jruby-(core|stdlib)-.+\\.jar")) {
        urls.add(basePath.resolve(strs[i]).toURL());
      }
    }

    return (URL[]) urls.toArray(new URL[urls.size()]);
  }

  private int launchJRuby(URL[] jars) throws Exception {
    System.setProperty("org.jruby.embed.class.path", "");
    URLClassLoader loader = new URLClassLoader(jars);
    Class scriptingContainerClass = Class.forName("org.jruby.embed.ScriptingContainer", true, loader);
    Object scriptingContainer = scriptingContainerClass.newInstance();

    Method argv = scriptingContainerClass.getDeclaredMethod("setArgv", new Class[] {String[].class});
    argv.invoke(scriptingContainer, new Object[] {args});
    Method setClassLoader = scriptingContainerClass.getDeclaredMethod("setClassLoader", new Class[] {ClassLoader.class});
    setClassLoader.invoke(scriptingContainer, new Object[] {loader});
    debug("invoking " + jarfile + " with: " + Arrays.deepToString(args));

    Method runScriptlet = scriptingContainerClass.getDeclaredMethod("runScriptlet", new Class[] {String.class});
    return ((Number) runScriptlet.invoke(scriptingContainer, new Object[] {
          "begin\n" +
          "require 'META-INF/init.rb'\n" +
          "require 'META-INF/main.rb'\n" +
          "0\n" +
          "rescue SystemExit => e\n" +
          "e.status\n" +
          "end"
          })).intValue();
  }

  private int start() throws Exception {
    URL[] u = extractJRuby();
    return launchJRuby(u);
  }

  private void debug(String msg) {
    if (debug) {
      System.out.println(msg);
    }
  }

  public void run() {
  }
 
  public static void main(String[] args) {
    try {
      int exit = new JarMain(args).start();
      System.exit(exit);
    } catch (Exception e) {
      Throwable t = e;
      while (t.getCause() != null && t.getCause() != t) {
        t = t.getCause();
      }

      if (isDebug()) {
        t.printStackTrace();
      }
      System.exit(1);
    }
  }

  private static boolean isDebug() {
    return System.getProperty("warbler.debug") != null;
  }
}
