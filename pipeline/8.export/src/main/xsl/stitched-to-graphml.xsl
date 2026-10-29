<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:g="http://graphml.graphdrawing.org/xmlns">
    <xsl:output method="xml" indent="yes" encoding="utf-8"/>
    <xsl:strip-space elements="*"/>

    <xsl:template match="/stitched-lineage">
        <g:graphml>
            <g:key id="operation" for="edge" attr.name="operation" attr.type="string"/>
            <g:key id="resolution" for="edge" attr.name="resolution" attr.type="string"/>
            <g:graph id="lineage" edgedefault="directed">
                <xsl:for-each-group select="stitched-flows/stitched-flow/@source | stitched-flows/stitched-flow/@target" group-by="string(.)">
                    <xsl:sort select="current-grouping-key()"/>
                    <g:node id="{current-grouping-key()}"/>
                </xsl:for-each-group>
                <xsl:for-each select="stitched-flows/stitched-flow">
                    <xsl:sort select="@id"/>
                    <g:edge id="{@id}" source="{@source}" target="{@target}">
                        <g:data key="operation"><xsl:value-of select="@operation"/></g:data>
                        <g:data key="resolution"><xsl:value-of select="@resolution-status"/></g:data>
                    </g:edge>
                </xsl:for-each>
            </g:graph>
        </g:graphml>
    </xsl:template>
</xsl:stylesheet>
