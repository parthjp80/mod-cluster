<%@ page contentType="text/plain;charset=UTF-8" session="false" trimDirectiveWhitespaces="true" %>
<%@ page import="java.net.InetAddress" %>
<%-- Session-less endpoint: every request is a fresh load-balancing decision. --%>
<%
    out.println("node=" + System.getProperty("jboss.node.name", "unknown")
            + " pod=" + InetAddress.getLocalHost().getHostName()
            + " ip=" + InetAddress.getLocalHost().getHostAddress()
            + " proxy=" + request.getHeader("X-Served-By-Proxy"));
%>
