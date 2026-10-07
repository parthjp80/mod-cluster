<%@ page contentType="text/html;charset=UTF-8" %>
<%@ page import="java.net.InetAddress, java.lang.management.*" %>
<%
    // Creates an HTTP session: mod_cluster will pin you to this node via the
    // JSESSIONID ".<jvmRoute>" suffix (sticky sessions).
    Integer hits = (Integer) session.getAttribute("hits");
    hits = (hits == null) ? 1 : hits + 1;
    session.setAttribute("hits", hits);

    String node = System.getProperty("jboss.node.name", "unknown");
    String host = InetAddress.getLocalHost().getHostName();
    String ip   = InetAddress.getLocalHost().getHostAddress();
    MemoryUsage heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
    double sysLoad = ManagementFactory.getOperatingSystemMXBean().getSystemLoadAverage();
    String via = request.getHeader("X-Served-By-Proxy");
%>
<!DOCTYPE html>
<html>
<head>
  <title>mod_cluster demo - <%= node %></title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 2rem; background: #f6f7f9; color: #1d2330; }
    .card { background: #fff; border-radius: 8px; padding: 1.5rem; max-width: 40rem; box-shadow: 0 1px 3px rgba(0,0,0,.12); }
    td { padding: .25rem 1rem .25rem 0; } td:first-child { color: #5b6475; }
    code { background: #eef0f4; padding: .1rem .3rem; border-radius: 4px; }
  </style>
</head>
<body>
<div class="card">
  <h1>Served by <code><%= node %></code></h1>
  <table>
    <tr><td>Pod / hostname</td><td><%= host %></td></tr>
    <tr><td>Pod IP</td><td><%= ip %></td></tr>
    <tr><td>Front-end Apache</td><td><%= via == null ? "(direct, not via Apache)" : via %></td></tr>
    <tr><td>Session ID</td><td><code><%= session.getId() %></code></td></tr>
    <tr><td>Hits in this session</td><td><%= hits %></td></tr>
    <tr><td>Heap used / max</td><td><%= heap.getUsed() / 1048576 %> MB / <%= heap.getMax() / 1048576 %> MB</td></tr>
    <tr><td>System load avg</td><td><%= String.format("%.2f", sysLoad) %></td></tr>
  </table>
  <p>Reload: you stay on the same node (sticky session).
     <a href="info.jsp">info.jsp</a> creates no session, so every request is balanced by load.</p>
</div>
</body>
</html>
