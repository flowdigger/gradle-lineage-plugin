<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:g="urn:xmlast:grammar"
                xmlns:c="urn:xmlast:comment" xmlns:t="urn:xmlast:token"
                xmlns:l="urn:xmlast:lineage" xmlns:fn="urn:xmlast:functions"
                xmlns:m="urn:git:metadata"
                xmlns:r="urn:xmlast:graph"
                exclude-result-prefixes="xs fn g t c l" expand-text="yes" version="3.0">
    <xsl:param name="collection"/>
    <xsl:param name="schema"/>

    <xsl:param name="select-pattern" select="'*.xir'"/>
    <xsl:output method="xml" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <xsl:mode on-no-match="shallow-copy"/>
    <xsl:variable name="docs"
                  select="collection(concat($collection, '?on-error=ignore;recurse=yes;select=', $select-pattern))"/>
    <!--
        Toplevel Scan all procedures
      -->
    <xsl:template match="/">
        <xsl:variable name="currentDate" select="xs:string(current-dateTime())"/>
        <xsl:variable name="currentDateFmt" select="replace(normalize-space($currentDate),
            '^(\d{2})-(\d{2})-(\d{4})\s+(.*)','$3-$1-$2T$4Z')"/>
        <!--        <xsl:variable name="procedures" select="$docs/g:ast/l:lineage-sequence[@type='procedure']"/>-->
        <xsl:variable name="views" select="$docs//view[string-length(@name) > 0]"/>

        <l:views xmlns:l="urn:xmlast:lineage"
                 schema="{$schema}"
                 collection="{$collection}"
                 creation-date="{$currentDateFmt}"
                 count="{count($views)}">
y
            <xsl:for-each select="$views">
                <xsl:sort select="@name"/>
                <xsl:variable name="name" select="@name"/>
                <xsl:variable name="calls" select=".//call"/>
                <xsl:variable name="called-by" select="$views[.//call[@name = $name]]"/>

                <l:view name="{$name}">
                    <xsl:copy-of select="ancestor::*/@* except ancestor::*/@entryRule"/>
                    <r:to name="{$name}">
                        <xsl:for-each select="from[string-length(@name) > 0]">
                            <r:from name="{@name}"/>
                        </xsl:for-each>
                    </r:to>
                </l:view>

            </xsl:for-each>
        </l:views>
        <xsl:message>end scan {$schema}</xsl:message>
    </xsl:template>


</xsl:stylesheet>
