<%@ page contentType="text/plain;charset=UTF-8" session="false" trimDirectiveWhitespaces="true" %>
<%--
  Raises the CPU load metric: spins ?threads=N busy threads for ?sec=S seconds.
  Note: the "cpu" metric is the system load average, which inside a container
  reflects the whole Kubernetes NODE, not just this pod.
--%>
<%
    final int sec = Integer.parseInt(request.getParameter("sec") == null ? "60" : request.getParameter("sec"));
    int threads = Integer.parseInt(request.getParameter("threads") == null ? "2" : request.getParameter("threads"));
    final long end = System.currentTimeMillis() + sec * 1000L;
    for (int i = 0; i < threads; i++) {
        Thread t = new Thread(() -> {
            double x = 0;
            while (System.currentTimeMillis() < end) { x += Math.sqrt(x + 1); }
        }, "burn-" + i);
        t.setDaemon(true);
        t.start();
    }
    out.println("node=" + System.getProperty("jboss.node.name") + " burning threads=" + threads + " for=" + sec + "s (returns immediately)");
%>
