<?xml version="1.0" encoding="UTF-8"?>
<!--
     call-app.xsl
     Create Application Descriptions for each Vortex App

     Jurgen Hildebrand (Jurgen.Hildebrand@ing.com)
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:fn="urn:xmlast:functions"
                xmlns:l="urn:xmlast:lineage"
                xmlns:r="urn:xmlast:graph"
                xmlns:m="urn:git:metadata"
                exclude-result-prefixes="xs fn" expand-text="yes" version="3.0">

    <xsl:param name="work-uri"/>
    <xsl:param name="output-ext">xml</xsl:param>

    <xsl:output method="xml" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <!--
    <xsl:mode on-no-match="shallow-copy"/>
    -->
<!--    <xsl:import href="utils.xsl"/>-->
    <xsl:import href="custom-tags.xsl"/>

    <!--
    Top Level Match Rule
    -->
    <xsl:template match="/*">
        <xsl:variable name="db-names" select="distinct-values(//database/@name)"/>
        <xsl:message>db-names: {$db-names}</xsl:message>
        <xsl:message>schema-names: {$schema-names}</xsl:message>
        <xsl:element name="{local-name(.)}">
            <xsl:apply-templates select="@*|node()"/>
        </xsl:element>
    </xsl:template>

    <!--
    Handle processors
    -->
    <xsl:template match="applicationcomponent[app]">
        <xsl:variable name="name" select="lower-case(replace(@name,' ','-'))"/>
        <xsl:variable name="app-path">{$work-uri}/lineage/app/xml/{$name}.{$output-ext}</xsl:variable>
        <xsl:message>generating: {$name} {$app-path}</xsl:message>
        <applicationcomponent path="{$app-path}">
            <xsl:copy-of select="@*,doc,properties"/>
        </applicationcomponent>
        <xsl:variable name="tree">
            <xsl:apply-templates select="app/(* except distributions),app/distributions"/>
        </xsl:variable>
        <xsl:result-document href="{$app-path}">
            <applicationcomponent name="{$name}" path="{$app-path}">
                <xsl:copy-of select="@*,doc,properties"/>
                <xsl:apply-templates select="$tree" mode="post-process"/>
            </applicationcomponent>
        </xsl:result-document>
    </xsl:template>
    <xsl:template match="applicationcomponent"/>

    <!--
     Handle manual defined tables
    -->
    <xsl:template match="tables">
        <xsl:element name="{local-name(.)}">
            <xsl:attribute name="class">manual-entry</xsl:attribute>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:element>
    </xsl:template>

    <!--
    Handle calls to procedures
    -->
    <xsl:template match="calls">
        <xsl:variable name="db" select="ancestor::database[1]/@name"/>
        <xsl:sequence select="fn:emit-calls($db,self::calls)"/>
    </xsl:template>



    <!--
    Merge multiple database entries with same name
    -->
    <xsl:template match="applicationcomponent[app]" mode="post-process">
        <xsl:element name="{local-name(.)}">
            <xsl:copy-of select="@*"/>
            <xsl:for-each-group select="database" group-by="@name">
                <xsl:sort select="current-grouping-key()"/>
                <database name="{current-grouping-key()}">
                    <xsl:apply-templates select="current-group()/calls" mode="post-process"/>
                    <xsl:apply-templates select="current-group()/events" mode="post-process"/>
                    <xsl:apply-templates select="current-group()/*[not(self::events or self::calls)]" mode="post-process"/>
                </database>
            </xsl:for-each-group>
        </xsl:element>
    </xsl:template>

    <!--
    Dedup adjacent multiple calls
    -->
    <xsl:template match="calls[call]" mode="post-process">
        <xsl:variable name="calls" select="call"/>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each-group group-adjacent="@name" select="$calls">
                <xsl:copy select="current-group()[1]">
                    <xsl:copy-of select="@*"/>
                    <xsl:if test="count(current-group()) gt 1">
                        <xsl:attribute name="count" select="count(current-group())"/>
                    </xsl:if>
                    <xsl:apply-templates select="current-group()[1]/node()" mode="post-process"/>
                </xsl:copy>
            </xsl:for-each-group>
        </xsl:copy>
    </xsl:template>



    <!--
    Default rules when specific rules not match
    -->
    <xsl:template match="l:referenced-tables" mode="#all">
        <tables>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </tables>
    </xsl:template>

    <xsl:template match="r:to[string-length(@name)=0 or not(r:from)]"/>
    <xsl:template match="r:from[string-length(@name)=0]"/>

<!--    <xsl:template match="r:graph" mode="#all">-->
<!--        <graph xmlns="urn:xmlast:graph">-->
<!--            <xsl:copy-of select="r:to" copy-namespaces="no"/>-->
<!--        </graph>-->
<!--    </xsl:template>-->

    <xsl:template match="m:*|l:*" mode="#all">
        <!-- move from other name space to default name space -->
        <xsl:element name="{local-name(.)}">
            <xsl:apply-templates select="@*|node()"/>
        </xsl:element>
    </xsl:template>

    <xsl:template match="@*|node()" mode="#all">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>

<!-- start utility functions -->
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
    <xsl:variable name="table-map" select="fn:map-res('table-index',$schema-names)" as="map(*)"/>

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
        <xsl:variable name="doc-base" select="$work-uri || '/lineage/' || $res || '.' || $db"/>
        <xsl:choose>
            <xsl:when test="doc-available($doc-base || '.xml')">
                <xsl:message>loading: {$doc-base}.xml</xsl:message>
                <xsl:sequence select="doc($doc-base || '.xml')/*"/>
            </xsl:when>
            <xsl:when test="doc-available($doc-base || '.xir')">
                <xsl:message>loading: {$doc-base}.xir</xsl:message>
                <xsl:sequence select="doc($doc-base || '.xir')/*"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:message>not available: {$doc-base} (xml or xir)</xsl:message>
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
            <xsl:variable name="procedure-section" as="node()*">
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
            </xsl:variable>
            <procedures>
                <xsl:sequence select="$procedure-section"/>
            </procedures>
            <tables>
                <xsl:variable name="all-tables-used" select="distinct-values($procedure-section//table/@name)"/>
                <xsl:for-each select="$all-tables-used">
                    <xsl:sort select="."/>
                    <xsl:variable name="table-name" select="."/>
                    <xsl:variable name="table-ref" select="$table-map($db)//table[@name=$table-name]"/>
                    <xsl:copy-of select="$table-ref"/>
                </xsl:for-each>
            </tables>
        </xsl:if>

    </xsl:function>


    <!-- end utility functions -->

    <!-- start custom tags -->
    <!--
    Handle Current tables
    -->

    <xsl:template match="current-tables">
        <xsl:variable name="db" select="ancestor::database[1]/@name"/>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:apply-templates select="$doc('current-tables')($db)/*" mode="current-tables">
                <xsl:sort select="@original-name"/>
            </xsl:apply-templates>
        </xsl:copy>
    </xsl:template>
    <xsl:template match="item" mode="current-tables">
       <xsl:copy>
           <xsl:copy-of select="@*"/>
           <r:to name="{@current-name}">
               <r:from name="{@original-name}"/>
           </r:to>
           <xsl:if test="@current-tree-name">
               <r:to name="{@current-name}">
                   <r:from name="{@current-tree-name}"/>
               </r:to>
           </xsl:if>
       </xsl:copy>
    </xsl:template>
    <!--
        Handle distributions
    -->
    <xsl:template match="distribution">
        <xsl:variable name="class-code" select="@class-code"/>
        <xsl:variable name="definition" select="$doc('distribution-definition')/class[@class-code = $class-code]"/>
        <xsl:variable name="class" select="$doc('distribution-class')/item[@class-code = $class-code]"/>
        <distribution class="{$class-code}" source-schema="{$definition/@source-schema}" target-schema="{$definition/@target-schema}">
            <xsl:copy-of select="$definition/@*"/>
            <xsl:copy-of select="$class/@*"/>
            <xsl:apply-templates select="$definition/transfer"/>
        </distribution>
    </xsl:template>

    <xsl:template match="transfer">
        <xsl:variable name="target-schema" select="../@target-schema"/>
        <xsl:variable name="source-schema" select="../@source-schema"/>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <r:to name="{$target-schema}.{@target-table}">
                <r:from name="{$source-schema}.{@source-table}"/>
            </r:to>
            <xsl:if test="@post-proc">
                <database name="{$target-schema}">
                    <xsl:variable name="call-proc">
                        <call name="{@post-proc}"/>
                    </xsl:variable>
                    <xsl:sequence select="
                    fn:emit-calls($target-schema,$call-proc)"/>
                </database>
            </xsl:if>
        </xsl:copy>
    </xsl:template>
    <!--
     Handle SDU
    -->
    <xsl:template match="sdm-import-table-definition">
        <tables component="load" mode="writer">
            <xsl:apply-templates select="$doc('sdm-import-table-definition')/item" mode="sdu">
                <xsl:sort select="lower-case(@target-table)"/>
            </xsl:apply-templates>
        </tables>
    </xsl:template>
    <xsl:template match="item" mode="sdu">
        <table name="{@target-table}"/>
    </xsl:template>
    <xsl:template match="vxx-dispatch">
        <xsl:variable name="db" select="ancestor::database[1]/@name"/>
        <flows>
            <xsl:apply-templates select="$doc('vxx-dispatch')/interface[@interface-type=$db]/*" mode="vxx">
                <xsl:with-param name="db" select="$db" tunnel="true"/>
            </xsl:apply-templates>
        </flows>
    </xsl:template>
    <xsl:template match="event" mode="vxx">
        <flow name="{@source-event-type}" event-type="{@source-event-type}">
            <tables class="queues">
                <xsl:apply-templates select="job" mode="vxx"/>
            </tables>
        </flow>
    </xsl:template>
    <xsl:template match="job" mode="vxx">
        <table name="{@target-queue}" event="{@target-event-type}" is="writer"/>
    </xsl:template>
    <!--
     Handle VDE
    -->
    <xsl:template match="vde-config">
        <xsl:variable name="db" select="ancestor::database[1]/@name"/>
        <events>
            <xsl:apply-templates select="$doc('vde-event')/interface[@interface-type=$db]/*" mode="vde">
                <xsl:with-param name="db" select="$db" tunnel="true"/>
            </xsl:apply-templates>
        </events>
    </xsl:template>
    <xsl:template match="event" mode="vde">
        <xsl:param name="db" tunnel="yes"/>
        <xsl:variable name="calls">
            <xsl:apply-templates mode="#current"/>
        </xsl:variable>
        <xsl:variable name="event-type" select="@event-type"/>
        <xsl:variable name="emit-calls" select="fn:emit-calls($db,$calls)" as="node()*"/>
        <event name="{@event-type}">
            <xsl:copy-of select="@*"/>
            <xsl:apply-templates select="$vde-config/interface[@interface-type=$db]/
                event[@event-type=$event-type]/*">
                <xsl:with-param name="emit-calls" select="$emit-calls" tunnel="true"/>
            </xsl:apply-templates>
            <procedures>
                <xsl:sequence select="$emit-calls//procedure"/>
            </procedures>
        </event>
    </xsl:template>
    <xsl:template match="@*[. = 'N']"/>
    <xsl:template match="channel">
        <xsl:param name="emit-calls" as="node()*" tunnel="true"/>
        <xsl:variable name="channel" select="@export-channel"/>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <exports>
                <xsl:apply-templates select="node()"/>
            </exports>
            <handlers>
                <xsl:sequence select="$emit-calls//handler[@channel = $channel]"/>
            </handlers>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="job" mode="vde">
        <xsl:param name="db" tunnel="true"/>
        <xsl:variable name="proc-name" select="@procedure-name"/>
        <xsl:variable name="tree" select="$call-tree-map($db)//l:call[@name=$proc-name]/*"/>
        <handler handler-type="{@handler-type}" channel="{@export-channel}">
            <call name="{$proc-name}">
                <xsl:if test="not(empty($tree))">
                    <xsl:apply-templates select="$tree"/>
                </xsl:if>
            </call>
        </handler>
    </xsl:template>
    <!--
     Handle VPP
    -->
    <xsl:template match="vpp-config">
        <xsl:variable name="db" select="ancestor::database[1]/@name"/>
        <flows>
            <xsl:apply-templates select="$doc('vpp-config')/interface[@interface-type=$db]/*" mode="vpp">
                <xsl:with-param name="db" select="$db" tunnel="yes"/>
            </xsl:apply-templates>
        </flows>
    </xsl:template>
    <xsl:template match="event" mode="vpp">
        <xsl:param name="db" tunnel="yes"/>
        <xsl:variable name="calls">
            <xsl:apply-templates mode="#current"/>
        </xsl:variable>
        <flow name="{@event-type}">
            <xsl:copy-of select="@*"/>
            <xsl:sequence select="fn:emit-calls($db,$calls)"/>
        </flow>
    </xsl:template>
    <xsl:template match="job" mode="vpp">
        <xsl:param name="db" tunnel="true"/>
        <xsl:variable name="proc-name" select="@sql-code"/>
        <xsl:variable name="tree" select="$call-tree-map($db)//l:procedure[@name=$proc-name]/*"/>
        <call name="{$proc-name}">
            <xsl:if test="not(empty($tree))">
                <xsl:apply-templates select="$tree"/>
            </xsl:if>
        </call>
    </xsl:template>
    <!--
     Handle Sync
     -->
    <xsl:template match="sync">
        <xsl:variable name="db" select="ancestor::database[1]/@name"/>
        <xsl:variable name="calls">
            <xsl:apply-templates select="$doc('sync')($db)/interface/*" mode="sync"/>
        </xsl:variable>
        <xsl:sequence select="fn:emit-calls($db,$calls)"/>
    </xsl:template>

    <!-- _query_table_name -->
    <xsl:template match="call" mode="sync">
        <xsl:copy>
            <xsl:copy-of select="@*"/>
        </xsl:copy>
    </xsl:template>



    <!--
     Handle Raw views
     -->
    <xsl:template match="raw-view-data">
        <xsl:variable name="db" select="ancestor::database[1]/@name"/>
        <xsl:apply-templates select="$doc('raw-view')($db)" mode="raw-view"/>
    </xsl:template>
    <xsl:template match="raw-view-data" mode="raw-view">
        <xsl:apply-templates mode="raw-view"/>
    </xsl:template>
    <xsl:template match="subscription" mode="raw-view">
        <tables component="raw-views" class="{@subscription-id}" mode="reader">
            <xsl:variable name="tables">
                <xsl:apply-templates select="table" mode="raw-view"/>
            </xsl:variable>
            <xsl:for-each-group select="$tables/table" group-by="@name">
                <xsl:sort select="current-grouping-key()"/>
                <xsl:sequence select="current-group()[1]"/>
            </xsl:for-each-group>
        </tables>
    </xsl:template>
    <xsl:template match="table" mode="raw-view">
        <table name="{lower-case(@table-name)}"/>
    </xsl:template>

    <!-- end custom tags -->

</xsl:stylesheet>
