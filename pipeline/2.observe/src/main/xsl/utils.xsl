<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:fn="urn:xmlast:functions"
                xmlns:l="urn:xmlast:lineage"
                xmlns:r="urn:xmlast:graph"
                xmlns:m="urn:git:metadata"
                exclude-result-prefixes="xs fn" expand-text="yes" version="3.0">
    <!--
    <xsl:param name="work-uri"/>
    -->
    <!--
Look up cross reference objects in other documents
-->
    <xsl:variable name="doc"
                  as="map(*)"
                  select="map {
                     'sdm-import-table-definition' : fn:config('sdp/sdm_import_table_definition.xml'),
                     'distribution-definition' : fn:config('sdp/distribution_definition.xml'),
                     'distribution-class' : fn:config('sdp/distribution_class.xml'),
                     'vde-event' : fn:config('sdp/vde_event.xml'),
                     'vde-config' : fn:config('sdp/vde_config.xml'),
                     'vpp-config' : fn:config('sdp/vpp_config.xml'),
                     'vxx-dispatch' : fn:config('sdp/vxx_dispatch.xml'),
                     'sync' : map {
                        'buss' : fn:config('buss/dmi_process_workflow_base.xml'),
                        'cons' : fn:config('cons/dmr_process_workflow_base.xml')
                     },
                     'raw-view' : map {
                        'buss' : fn:config('buss/raw_view_data.xml'),
                        'cons' : fn:config('cons/raw_view_data.xml')
                     },
                     'current-tables' : map {
                        'dsa' : fn:config('dsa/current_table.xml'),
                        'cons' : fn:config('cons/current_table.xml')
                     }
                  }"/>
    <xsl:variable name="schema-names"
                  select="distinct-values($doc('distribution-definition')/class/(@source-schema,@target-schema))"/>
    <xsl:variable name="call-tree-map" select="fn:map-res('call-tree',$schema-names)" as="map(*)"/>
    <xsl:variable name="procedure-map" select="fn:map-res('procedure',$schema-names)" as="map(*)"/>
    <xsl:variable name="vde-config" select="$doc('vde-config')"/>
    <!--
     Functions
     -->

    <xsl:function name="fn:config">
        <xsl:param name="part"/>
        <xsl:variable name="uri" select="$work-uri || '/configuration/' || $part"/>
        <xsl:message>fn:config({$uri})</xsl:message>
        <xsl:sequence select="doc($uri)/*"/>
    </xsl:function>
    <xsl:function name="fn:res">
        <xsl:param name="db"/>
        <xsl:param name="res"/>
        <xsl:variable name="doc-url" select="$work-uri || '/lineage/' || $res || '.' || $db || '.xml'"/>
        <xsl:choose>
            <xsl:when test="doc-available($doc-url)">
                <xsl:message>loading: {$doc-url}</xsl:message>
                <xsl:sequence select="doc($doc-url)/*"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:message>not available: {$doc-url}</xsl:message>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>
    <xsl:function name="fn:map-res" as="map(*)">
        <xsl:param name="res"/>
        <xsl:param name="schema-names"/>
        <xsl:map>
            <xsl:for-each select="$schema-names">
                <xsl:variable name="map-value" select="fn:res(.,$res)"/>
                <xsl:if test="not(empty($map-value))">
                    <xsl:map-entry key="." select="$map-value"/>
                </xsl:if>
            </xsl:for-each>
        </xsl:map>
    </xsl:function>
    <xsl:function name="fn:emit-calls">
        <xsl:param name="db"/>
        <xsl:param name="calls"/>
        <xsl:variable name="call-names" select="distinct-values($calls//call/@name)"/>
        <xsl:variable name="call-trees" select="$call-tree-map($db)/call"/>
        <xsl:if test="not(empty($call-names))">
            <xsl:variable name="trees">
                <xsl:for-each select="$call-names">
                    <xsl:variable name="proc-name" select="."/>
                    <xsl:sequence select="$call-trees[@name=$proc-name]"/>
                </xsl:for-each>
            </xsl:variable>
            <calls>
                <xsl:sequence select="$trees"/>
            </calls>
            <xsl:variable name="all-call-names" select="distinct-values($trees//call/@name)"/>
            <procedures>
                <xsl:for-each select="$all-call-names">
                    <xsl:sort select="."/>
                    <xsl:variable name="proc-name" select="."/>
                    <procedure name="{$proc-name}">
                        <xsl:variable name="proc-ref" select="$procedure-map($db)//l:procedure[@name=$proc-name]"/>
                        <xsl:copy-of select="$proc-ref/@*"/>
                        <xsl:apply-templates
                                select="$proc-ref/(l:referenced-tables|r:graph|m:*)"/>
                    </procedure>
                </xsl:for-each>
            </procedures>
        </xsl:if>

    </xsl:function>


</xsl:stylesheet>