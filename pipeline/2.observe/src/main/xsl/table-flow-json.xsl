<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:map="http://www.w3.org/2005/xpath-functions/map"
                xmlns:c="urn:table-flow-common"
                xmlns:f="urn:table-flow-sigma-json"
                exclude-result-prefixes="xs map c f"
                expand-text="yes">

    <xsl:output method="text" encoding="utf-8" omit-xml-declaration="yes"/>
    <xsl:strip-space elements="*"/>
    <xsl:mode on-no-match="shallow-skip"/>

    <xsl:include href="table-flow-common.xsl"/>

    <xsl:function name="f:edge-id" as="xs:string">
        <xsl:param name="procedure" as="xs:string"/>
        <xsl:param name="source" as="xs:string"/>
        <xsl:param name="target" as="xs:string"/>
        <xsl:sequence select="$procedure || '.' || $source || '-' || $target"/>
    </xsl:function>

    <xsl:template match="/">
        <xsl:variable name="docs"
                      select="collection(c:collection-uri(., $input-uri))"
                      as="document-node()*"/>
        <xsl:variable name="procedures" select="for $d in $docs return c:procedure-containers($d)" as="element()*"/>
        <xsl:variable name="first-uri" select="string((for $d in $docs return document-uri($d))[1])" as="xs:string"/>

        <xsl:variable name="resolved-schema"
                      select="c:resolve-schema($schema-name, $first-uri)"
                      as="xs:string"/>

        <xsl:variable name="tables"
                      select="distinct-values(for $p in $procedures return (c:reads($p), c:writes($p)))"
                      as="xs:string*"/>

        <xsl:variable name="edge-records" as="map(*)*">
            <xsl:for-each select="$procedures">
                <xsl:variable name="procedure" select="c:procedure-name(.)" as="xs:string"/>
                <xsl:variable name="reads" select="distinct-values(c:reads(.))" as="xs:string*"/>
                <xsl:variable name="writes" select="distinct-values(c:writes(.))" as="xs:string*"/>
                <xsl:for-each select="$reads">
                    <xsl:variable name="source" select="." as="xs:string"/>
                    <xsl:for-each select="$writes">
                        <xsl:variable name="target" select="." as="xs:string"/>
                        <xsl:sequence select="map {
                            'id': f:edge-id($procedure, $source, $target),
                            'source': $source,
                            'target': $target,
                            'label': $procedure,
                            'procedure': $procedure,
                            'size': 1
                        }"/>
                    </xsl:for-each>
                </xsl:for-each>
            </xsl:for-each>
        </xsl:variable>

        <xsl:variable name="edges" as="map(*)*">
            <xsl:for-each-group select="$edge-records" group-by="?id">
                <xsl:variable name="edge" select="current-group()[1]" as="map(*)"/>
                <xsl:sequence select="map:put($edge, 'size', count(current-group()))"/>
            </xsl:for-each-group>
        </xsl:variable>

        <xsl:variable name="nodes" as="map(*)*">
            <xsl:for-each select="$tables">
                <xsl:sort select="."/>
                <xsl:sequence select="map {
                    'id': .,
                    'label': .,
                    'type': 'table'
                }"/>
            </xsl:for-each>
        </xsl:variable>

        <xsl:variable name="payload" as="map(*)"
                      select="map {
                          'schema': $resolved-schema,
                          'nodes': array { $nodes },
                          'edges': array { $edges },
                          'meta': map {
                              'sourceCount': count($docs),
                              'procedureCount': count($procedures),
                              'tableCount': count($nodes),
                              'edgeCount': count($edges)
                          }
                      }"/>

        <xsl:sequence
                select="serialize($payload, map { 'method': 'json', 'indent': true(), 'omit-xml-declaration': true() })"/>
    </xsl:template>

</xsl:stylesheet>

