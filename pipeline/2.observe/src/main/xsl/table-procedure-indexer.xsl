<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:c="urn:table-flow-common"
                exclude-result-prefixes="xs c"
                expand-text="yes">

    <!--~
        Output: XML
        Indents output for readability.
    -->
    <xsl:output method="xml" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <xsl:mode on-no-match="shallow-skip"/>

    <xsl:include href="table-flow-common.xsl"/>

    <!--~
        Template: match="/"
        Description: Main entry point. Loads all relevant XML files, extracts procedures and views, determines schema name, and builds the table index.
    -->
    <xsl:template match="/">
        <xsl:variable name="docs"
                      select="c:docs-for-schema(., $input-uri, $schema-name)"
                      as="document-node()*"/>
        <xsl:variable name="first-uri" select="string((for $d in $docs return document-uri($d))[1])" as="xs:string"/>
        <xsl:variable name="procedures" select="for $d in $docs return c:procedure-containers($d)" as="element()*"/>
        <xsl:variable name="views" select="for $d in $docs return c:view-containers($d)" as="element()*"/>


        <xsl:variable name="resolved-schema"
                      select="c:resolve-schema($schema-name, $first-uri)"
                      as="xs:string"/>
        <xsl:message select="'Processing schema: ' || $resolved-schema"/>
        <tables schema="{$resolved-schema}" source-count="{count($docs)}"
                view-count="{count($views)}" procedure-count="{count($procedures)}">
            <!-- Process procedures: group by tables they read from or write to -->
            <xsl:for-each-group
                    select="for $p in $procedures return (c:reads($p), c:writes($p))"
                    group-by=".">
                <xsl:sort select="current-grouping-key()"/>

                <xsl:variable name="table" select="current-grouping-key()" as="xs:string"/>
                <table name="{$table}">
                    <xsl:message>table: {$table}</xsl:message>
                    <xsl:for-each select="$procedures[c:reads(.) = $table or c:writes(.) = $table]">
                        <xsl:sort select="c:procedure-name(.)"/>
                        <xsl:variable name="reads" select="exists(c:reads(.)[. = $table])"/>
                        <xsl:variable name="writes" select="exists(c:writes(.)[. = $table])"/>
                        <procedure name="{c:procedure-name(.)}">
                            <xsl:attribute name="access">
                                <xsl:choose>
                                    <xsl:when test="$reads and $writes">read/write</xsl:when>
                                    <xsl:when test="$reads">read</xsl:when>
                                    <xsl:when test="$writes">write</xsl:when>
                                    <xsl:otherwise>unknown</xsl:otherwise>
                                </xsl:choose>
                            </xsl:attribute>
                        </procedure>
                    </xsl:for-each>
                    <!-- Include views that depend on this table -->
                    <xsl:for-each select="$views[c:view-sources(.) = $table][string-length(c:view-name(.)) > 0]">
                        <xsl:sort select="c:view-name(.)"/>
                        <view name="{c:view-name(.)}" access="read"/>
                    </xsl:for-each>
                </table>
            </xsl:for-each-group>

            <!-- Process views: group by their source tables -->
            <xsl:for-each-group
                    select="for $v in $views return c:view-sources($v)"
                    group-by=".">
                <xsl:sort select="current-grouping-key()"/>

                <xsl:variable name="table" select="current-grouping-key()" as="xs:string"/>
                <!-- Only add if not already covered above -->
                <xsl:if test="not($procedures[c:reads(.) = $table or c:writes(.) = $table])">
                    <table name="{$table}">
                        <xsl:message>table (from views): {$table}</xsl:message>
                        <xsl:for-each select="$views[c:view-sources(.) = $table]">
                            <xsl:sort select="c:view-name(.)"/>
                            <view name="{c:view-name(.)}" access="read"/>
                        </xsl:for-each>
                    </table>
                </xsl:if>
            </xsl:for-each-group>
        </tables>
    </xsl:template>

</xsl:stylesheet>
