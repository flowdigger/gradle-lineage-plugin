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
        <xsl:variable name="java-namespace-bindings" as="element(binding)*">
            <xsl:for-each select="$tree//java-lineage[@source-uri != '' and @domain != '']">
                <xsl:variable name="domain" as="xs:string" select="fn:norm(@domain)"/>
                <xsl:variable name="source-uri" as="xs:string" select="normalize-space(@source-uri)"/>
                <xsl:variable name="java-flow-candidates" as="xs:string*"
                              select="(
                                $source-uri || 'direct-flow.' || $domain || '.xml',
                                $source-uri || $domain || '.seed.xml'
                              )"/>
                <xsl:for-each select="$java-flow-candidates[doc-available(.)]">
                    <xsl:for-each select="doc(.)/direct-flows/java-namespaces/namespace[@prefix != '' and @package != '']">
                        <binding prefix="{@prefix}" package="{@package}"/>
                    </xsl:for-each>
                </xsl:for-each>
            </xsl:for-each>
        </xsl:variable>
        <xsl:result-document href="{$app-path}">
            <applicationcomponent name="{$name}" path="{$app-path}">
                <xsl:for-each-group select="$java-namespace-bindings" group-by="@prefix">
                    <xsl:variable name="packages" as="xs:string*" select="distinct-values(current-group()/@package ! string(.))"/>
                    <xsl:if test="count($packages) gt 1">
                        <xsl:message terminate="yes">Conflicting Java namespace prefix '{current-grouping-key()}' for app '{$name}': {string-join($packages, ', ')}</xsl:message>
                    </xsl:if>
                    <xsl:namespace name="{current-grouping-key()}" select="'java:' || $packages[1]"/>
                </xsl:for-each-group>
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


    <!-- start custom tags -->

    <!-- end custom tags -->

</xsl:stylesheet>
