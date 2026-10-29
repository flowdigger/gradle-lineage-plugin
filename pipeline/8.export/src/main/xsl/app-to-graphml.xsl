<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:r="urn:xmlast:graph"
                xmlns:g="http://graphml.graphdrawing.org/xmlns"
                exclude-result-prefixes="r">
    <xsl:output method="xml" indent="yes" encoding="utf-8"/>
    <xsl:strip-space elements="*"/>

    <xsl:template match="/applicationcomponent">
        <xsl:variable name="processor" select="string(@name)"/>
        <g:graphml>
            <g:key id="processor" for="graph" attr.name="processor" attr.type="string"/>
            <g:key id="database" for="edge" attr.name="database" attr.type="string"/>
            <g:key id="procedure" for="edge" attr.name="procedure" attr.type="string"/>
            <g:graph id="lineage" edgedefault="directed">
                <g:data key="processor"><xsl:value-of select="$processor"/></g:data>
                <xsl:for-each-group select=".//r:to/@name | .//r:from/@name" group-by="string(.)">
                    <xsl:sort select="current-grouping-key()"/>
                    <g:node id="{current-grouping-key()}"/>
                </xsl:for-each-group>
                <xsl:for-each select="database">
                    <xsl:variable name="db" select="string(@name)"/>
                    <xsl:for-each select="procedures/procedure">
                        <xsl:variable name="proc" select="string(@name)"/>
                        <xsl:for-each select="r:graph/r:to">
                            <xsl:variable name="to" select="string(@name)"/>
                            <xsl:for-each select="r:from">
                                <xsl:variable name="from" select="string(@name)"/>
                                <g:edge id="{concat('edge-', generate-id(.))}" source="{$from}" target="{$to}">
                                    <g:data key="database"><xsl:value-of select="$db"/></g:data>
                                    <g:data key="procedure"><xsl:value-of select="$proc"/></g:data>
                                </g:edge>
                            </xsl:for-each>
                        </xsl:for-each>
                    </xsl:for-each>
                </xsl:for-each>
            </g:graph>
        </g:graphml>
    </xsl:template>
</xsl:stylesheet>
