<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:map="http://www.w3.org/2005/xpath-functions/map"
                expand-text="yes">
    <xsl:output method="text" encoding="utf-8" omit-xml-declaration="yes"/>
    <xsl:strip-space elements="*"/>

    <xsl:template match="/">
        <xsl:variable name="nodes" as="map(*)*">
            <xsl:for-each-group select="/stitched-lineage/stitched-flows/stitched-flow/@source | /stitched-lineage/stitched-flows/stitched-flow/@target"
                                group-by="string(.)">
                <xsl:sequence select="map{'id': current-grouping-key(), 'label': current-grouping-key(), 'type': 'entity'}"/>
            </xsl:for-each-group>
        </xsl:variable>

        <xsl:variable name="edges" as="map(*)*">
            <xsl:for-each select="/stitched-lineage/stitched-flows/stitched-flow">
                <xsl:sort select="@id"/>
                <xsl:sequence select="map{
                    'id': string(@id),
                    'source': string(@source),
                    'target': string(@target),
                    'label': string(@operation),
                    'size': 1
                }"/>
            </xsl:for-each>
        </xsl:variable>

        <xsl:variable name="payload" as="map(*)"
                      select="map{
                        'schema': 'uniform',
                        'nodes': array { $nodes },
                        'edges': array { $edges },
                        'meta': map{
                            'nodeCount': count($nodes),
                            'edgeCount': count($edges)
                        }
                      }"/>

        <xsl:sequence select="serialize($payload, map{'method': 'json', 'indent': true()})"/>
    </xsl:template>
</xsl:stylesheet>
