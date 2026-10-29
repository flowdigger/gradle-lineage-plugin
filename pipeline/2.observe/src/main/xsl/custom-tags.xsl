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


    <!--
   Handle Current tables
   -->
    <xsl:template match="current-tables">
        <xsl:variable name="db" select="ancestor::database[1]/@name"/>
        <copy-table-set component="current" class="current-tables">
            <xsl:apply-templates select="$doc('current-tables')($db)/*" mode="current-tables">
                <xsl:sort select="@original-name"/>
            </xsl:apply-templates>
        </copy-table-set>
    </xsl:template>
    <xsl:template match="item" mode="current-tables">
        <xsl:sequence select="."/>
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
            <!--
            enable for full contents
            -->
            <xsl:apply-templates select="$definition/transfer"/>
        </distribution>
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
            <xsl:apply-templates select="$doc('sync')($db)/interface/*" mode="sync">
                <xsl:with-param name="db" select="$db"/>
            </xsl:apply-templates>
        </xsl:variable>
        <xsl:sequence select="fn:emit-calls($db,$calls)"/>
    </xsl:template>

    <!-- _query_table_name -->
    <xsl:template match="call" mode="sync">
        <xsl:param name="db"/>
        <xsl:variable name="proc-name" select="@_procedure"/>
        <xsl:variable name="tree" select="$call-tree-map($db)//l:call[@name=$proc-name]"/>
        <xsl:if test="not(empty($tree))">
            <xsl:apply-templates select="$tree"/>
        </xsl:if>
    </xsl:template>
    <xsl:template match="job[@_query_table_name]" mode="sync">
        <table name="{@_query_table_name}"/>
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

</xsl:stylesheet>