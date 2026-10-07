<%@ page contentType="text/plain;charset=UTF-8" session="false" trimDirectiveWhitespaces="true" %>
<%--
  Raises the BUSYNESS load metric on THIS node: each call occupies one
  Undertow worker thread for ?sec=N seconds (default 30).
  Fire many in parallel to saturate the worker pool.
--%>
<%
    int sec = Integer.parseInt(request.getParameter("sec") == null ? "30" : request.getParameter("sec"));
    Thread.sleep(sec * 1000L);
    out.println("node=" + System.getProperty("jboss.node.name") + " slept=" + sec + "s");
%>
