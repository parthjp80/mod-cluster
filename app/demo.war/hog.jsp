<%@ page contentType="text/plain;charset=UTF-8" session="false" trimDirectiveWhitespaces="true" %>
<%@ page import="java.util.*, java.lang.management.*" %>
<%--
  Raises the HEAP load metric on THIS node.
    hog.jsp?mb=250    allocate and retain up to 250 MB (1 MB chunks, capped at ~85% heap)
    hog.jsp?release=1 drop everything and run GC
--%>
<%
    @SuppressWarnings("unchecked")
    List<byte[]> hoard = (List<byte[]>) application.getAttribute("hoard");
    if (hoard == null) {
        hoard = Collections.synchronizedList(new ArrayList<byte[]>());
        application.setAttribute("hoard", hoard);
    }
    if (request.getParameter("release") != null) {
        hoard.clear();
        System.gc();
    } else {
        int mb = Integer.parseInt(Optional.ofNullable(request.getParameter("mb")).orElse("100"));
        Runtime rt = Runtime.getRuntime();
        for (int i = 0; i < mb; i++) {
            // Safety valve: never push the heap past ~85% so the demo can't OOM the server.
            if (rt.totalMemory() - rt.freeMemory() > rt.maxMemory() * 0.85) {
                System.gc();
                if (rt.totalMemory() - rt.freeMemory() > rt.maxMemory() * 0.85) break;
            }
            byte[] chunk = new byte[1024 * 1024];
            Arrays.fill(chunk, (byte) 1);
            hoard.add(chunk);
        }
    }
    MemoryUsage heap = ManagementFactory.getMemoryMXBean().getHeapMemoryUsage();
    out.println("node=" + System.getProperty("jboss.node.name") + " hoarded=" + hoard.size() + "MB heapUsed=" + (heap.getUsed() / 1048576) + "MB heapMax=" + (heap.getMax() / 1048576) + "MB");
%>
